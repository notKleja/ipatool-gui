import Foundation
import Observation

@MainActor
@Observable
final class DiscoverViewModel {
    var query = "" { didSet { scheduleSearch() } }
    var platform: AppPlatform { didSet { if oldValue != platform { scheduleSearch(immediately: true) } } }
    private(set) var results: [AppStoreApp] = []
    private(set) var isSearching = false
    private(set) var error: EngineError?
    private(set) var hasSearched = false

    @ObservationIgnored private let service: any IPAToolServing
    @ObservationIgnored private let metadata: any AppMetadataProviding
    @ObservationIgnored private let limit: () -> Int
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private let debounce: Duration

    init(service: any IPAToolServing, metadata: any AppMetadataProviding, platform: AppPlatform,
         limit: @escaping () -> Int, debounce: Duration = .milliseconds(400)) {
        self.service = service
        self.metadata = metadata
        self.platform = platform
        self.limit = limit
        self.debounce = debounce
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func scheduleSearch(immediately: Bool = false) {
        searchTask?.cancel()
        let term = trimmedQuery
        guard !term.isEmpty else {
            results = []
            isSearching = false
            error = nil
            hasSearched = false
            return
        }
        searchTask = Task { [weak self, debounce] in
            if !immediately {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }
            await self?.search(term: term)
        }
    }

    func retry() { scheduleSearch(immediately: true) }

    private func search(term: String) async {
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            let apps = try await service.search(term: term, limit: limit(), platform: platform)
            guard !Task.isCancelled else { return }
            results = apps
            hasSearched = true
            let ids = apps.map(\.id)
            Task.detached { [metadata] in await metadata.prefetch(ids: ids) }
        } catch {
            guard !Task.isCancelled else { return }
            let engineError = EngineError.wrap(error)
            guard !engineError.isCancellation else { return }
            self.error = engineError
            results = []
            hasSearched = true
        }
    }
}
