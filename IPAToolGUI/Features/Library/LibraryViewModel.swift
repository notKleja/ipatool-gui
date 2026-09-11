import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    private(set) var apps: [AppStoreApp] = []
    private(set) var isLoading = false
    private(set) var error: EngineError?
    private(set) var hasMore = true
    private(set) var totalCount = 0
    var filter = ""

    @ObservationIgnored private let service: any IPAToolServing
    @ObservationIgnored private let metadata: any AppMetadataProviding
    @ObservationIgnored private var nextPage = 1
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    let pageSize: Int

    init(service: any IPAToolServing, metadata: any AppMetadataProviding, pageSize: Int = 25) {
        self.service = service
        self.metadata = metadata
        self.pageSize = pageSize
    }

    var filteredApps: [AppStoreApp] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let base = apps.sorted { ($0.purchaseDate ?? .distantPast) > ($1.purchaseDate ?? .distantPast) }
        guard !needle.isEmpty else { return base }
        return base.filter { $0.name.lowercased().contains(needle) || $0.bundleID.lowercased().contains(needle) }
    }

    func refresh() {
        loadTask?.cancel()
        apps = []
        nextPage = 1
        hasMore = true
        error = nil
        loadMore()
    }

    func loadMoreIfNeeded(current app: AppStoreApp) {
        guard hasMore, !isLoading, let last = filteredApps.last, last.id == app.id, filter.isEmpty else { return }
        loadMore()
    }

    func loadMore() {
        guard hasMore, loadTask == nil || loadTask?.isCancelled == true || !isLoading else { return }
        let page = nextPage
        loadTask = Task { [weak self] in
            await self?.load(page: page)
        }
    }

    private func load(page: Int) async {
        isLoading = true
        error = nil
        defer { isLoading = false; loadTask = nil }
        do {
            let result = try await service.purchasedApps(page: page, pageSize: pageSize)
            guard !Task.isCancelled else { return }
            let known = Set(apps.map(\.id))
            apps.append(contentsOf: result.apps.filter { !known.contains($0.id) })
            totalCount = result.totalCount
            hasMore = result.hasMore(pageSize: pageSize)
            nextPage = page + 1
            let ids = result.apps.map(\.id)
            Task.detached { [metadata] in await metadata.prefetch(ids: ids) }
        } catch {
            guard !Task.isCancelled else { return }
            let engineError = EngineError.wrap(error)
            guard !engineError.isCancellation else { return }
            self.error = engineError
        }
    }
}
