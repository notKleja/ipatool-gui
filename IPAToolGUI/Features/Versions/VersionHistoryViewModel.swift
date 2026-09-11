import Foundation
import Observation

/// Row in the version table. Metadata resolves lazily; until then only the external ID is known.
struct VersionRow: Identifiable, Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case pending
        case resolved(AppVersion)
        case failed(EngineErrorKind)
    }

    let externalID: ExternalVersionID
    var status: Status = .pending

    var id: ExternalVersionID { externalID }

    var version: AppVersion? {
        if case .resolved(let version) = status { return version }
        return nil
    }

    var displayVersion: String {
        switch status {
        case .pending: "…"
        case .resolved(let version): version.displayVersion.isEmpty ? "Unknown" : version.displayVersion
        case .failed: "Unavailable"
        }
    }

    var releaseDate: Date? { version?.releaseDate }
}

@MainActor
@Observable
final class VersionHistoryViewModel {
    private(set) var rows: [VersionRow] = []
    private(set) var isLoadingList = false
    private(set) var error: EngineError?
    private(set) var resolvedCount = 0

    @ObservationIgnored private let service: any IPAToolServing
    @ObservationIgnored private let appID: Int64
    @ObservationIgnored private let maxConcurrentLookups: Int
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(service: any IPAToolServing, appID: Int64, maxConcurrentLookups: Int = 3) {
        self.service = service
        self.appID = appID
        self.maxConcurrentLookups = max(1, maxConcurrentLookups)
    }

    var totalCount: Int { rows.count }
    var isResolving: Bool { !rows.isEmpty && resolvedCount < rows.count }

    func load() {
        loadTask?.cancel()
        loadTask = Task { await run() }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func run() async {
        isLoadingList = true
        error = nil
        resolvedCount = 0
        defer { isLoadingList = false }
        let ids: [ExternalVersionID]
        do {
            ids = try await service.versions(appID: appID)
        } catch {
            let engineError = EngineError.wrap(error)
            if !engineError.isCancellation { self.error = engineError }
            return
        }
        guard !Task.isCancelled else { return }
        rows = ids.sorted(by: >).map { VersionRow(externalID: $0) }
        isLoadingList = false
        await resolveAll(ids: rows.map(\.externalID))
    }

    /// Resolves metadata with bounded concurrency; newest IDs first.
    private func resolveAll(ids: [ExternalVersionID]) async {
        let service = service
        let appID = appID
        await withTaskGroup(of: (ExternalVersionID, VersionRow.Status).self) { group in
            var iterator = ids.makeIterator()
            var inFlight = 0
            func addNext() {
                guard let next = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    do {
                        let version = try await service.versionMetadata(appID: appID, externalVersionID: next)
                        return (next, .resolved(version))
                    } catch {
                        let engineError = EngineError.wrap(error)
                        return (next, .failed(engineError.kind))
                    }
                }
            }
            for _ in 0..<maxConcurrentLookups { addNext() }
            while inFlight > 0, let (id, status) = await group.next() {
                inFlight -= 1
                if Task.isCancelled { group.cancelAll(); break }
                apply(id: id, status: status)
                addNext()
            }
        }
    }

    private func apply(id: ExternalVersionID, status: VersionRow.Status) {
        guard let index = rows.firstIndex(where: { $0.externalID == id }) else { return }
        rows[index].status = status
        resolvedCount += 1
        if case .failed(.cancelled) = status { resolvedCount -= 1 }
    }

    /// Rows ordered by release date when known, keeping unresolved rows in ID order.
    var sortedRows: [VersionRow] {
        rows.sorted { lhs, rhs in
            switch (lhs.releaseDate, rhs.releaseDate) {
            case let (l?, r?): return l > r
            case (nil, nil): return lhs.externalID > rhs.externalID
            case (nil, _?): return false
            case (_?, nil): return true
            }
        }
    }
}
