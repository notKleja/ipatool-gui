import Foundation
import Observation
import AppKit

/// Bounded download queue. Owns every ipatool download process and the persisted history.
@MainActor
@Observable
final class DownloadManager {
    private(set) var items: [DownloadItem] = []
    /// Set when a download failed because the account has no license; the UI offers "Get & Download".
    var licensePrompt: DownloadItem?

    var maxConcurrent: Int { didSet { pump() } }
    var revealOnCompletion = false
    var conflictPolicy: FileConflictPolicy = .ask

    @ObservationIgnored private let service: any IPAToolServing
    @ObservationIgnored private let store: DownloadHistoryStore?
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    init(service: any IPAToolServing, store: DownloadHistoryStore?, maxConcurrent: Int = 1) {
        self.service = service
        self.store = store
        self.maxConcurrent = max(1, maxConcurrent)
        if let store {
            items = store.load().sorted { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: - Queries

    var activeItems: [DownloadItem] { items.filter { $0.state.isActive } }
    var finishedItems: [DownloadItem] { items.filter { $0.state.isTerminal } }
    var activeCount: Int { activeItems.count }

    func item(id: UUID) -> DownloadItem? { items.first { $0.id == id } }

    /// Destination we will hand to ipatool, or nil when the version isn't known ahead of time.
    static func plannedDestination(for request: DownloadRequest) -> URL? {
        if let explicit = request.explicitDestination { return explicit }
        guard let version = request.requestedVersion, !version.isEmpty else { return nil }
        let name = FilenameSanitizer.packageFilename(appName: request.appName, version: version,
                                                     platform: request.platform, bundleID: request.bundleID)
        return request.destinationDirectory.appendingPathComponent(name)
    }

    /// Existing file that a download would overwrite, if any.
    static func conflictingFile(for request: DownloadRequest) -> URL? {
        guard let planned = plannedDestination(for: request), FileManager.default.fileExists(atPath: planned.path) else { return nil }
        return planned
    }

    // MARK: - Mutations

    @discardableResult
    func enqueue(_ request: DownloadRequest) -> DownloadItem {
        let item = DownloadItem(request: request)
        items.insert(item, at: 0)
        persist()
        pump()
        return item
    }

    func cancel(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].state.isActive else { return }
        if let task = tasks[id] {
            task.cancel()
        } else {
            items[index].state = .cancelled
            items[index].completedAt = .now
            persist()
        }
    }

    func retry(id: UUID, acquireLicense: Bool? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].state.isTerminal else { return }
        var request = items[index].request
        if let acquireLicense { request.acquireLicense = acquireLicense }
        items.remove(at: index)
        enqueue(request)
    }

    func downloadAgain(id: UUID) {
        guard let item = item(id: id) else { return }
        enqueue(item.request)
    }

    /// Removes the history entry only; the downloaded file is left untouched.
    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].state.isActive { cancel(id: id) }
        items.remove(at: index)
        if licensePrompt?.id == id { licensePrompt = nil }
        persist()
    }

    func clearFinished() {
        items.removeAll { $0.state.isTerminal }
        persist()
    }

    func cancelAll() {
        for item in activeItems { cancel(id: item.id) }
    }

    // MARK: - Scheduling

    private func pump() {
        let running = tasks.count
        guard running < maxConcurrent else { return }
        let queued = items.filter { $0.state == .queued && tasks[$0.id] == nil }.sorted { $0.createdAt < $1.createdAt }
        for item in queued.prefix(maxConcurrent - running) {
            let id = item.id
            tasks[id] = Task { [weak self] in
                await self?.perform(id: id)
            }
        }
    }

    private func update(_ id: UUID, _ body: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        body(&items[index])
    }

    private func perform(id: UUID) async {
        defer {
            tasks[id] = nil
            persist()
            pump()
        }
        guard let item = item(id: id) else { return }
        let request = item.request
        update(id) { $0.state = .preparing; $0.startedAt = .now; $0.failure = nil; $0.progress = nil }

        let directory = request.destinationDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fail(id, EngineError(kind: .outputNotWritable, rawMessage: error.localizedDescription))
            return
        }
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            fail(id, EngineError(kind: .outputNotWritable, rawMessage: "\(directory.path) is not writable"))
            return
        }

        var output = Self.plannedDestination(for: request) ?? directory
        if request.explicitDestination == nil, conflictPolicy == .uniqueName, output != directory {
            output = FilenameSanitizer.uniqueURL(for: output)
        }
        update(id) { $0.destinationURL = output == directory ? nil : output }

        do {
            if request.acquireLicense {
                update(id) { $0.state = .acquiringLicense }
                let license = try await service.acquireLicense(bundleID: request.bundleID, platform: request.platform)
                update(id) { $0.licenseAcquired = !license.alreadyOwned }
            }
            try Task.checkCancellation()
            update(id) { $0.state = .downloading }
            let outcome = try await service.download(
                appID: request.appID, platform: request.platform, output: output,
                externalVersionID: request.externalVersionID, acquireLicense: request.acquireLicense
            ) { [weak self] progress in
                Task { @MainActor in self?.update(id) { $0.progress = progress.fraction } }
            }
            update(id) {
                $0.state = .completed
                $0.progress = 1
                $0.destinationURL = outcome.fileURL
                $0.completedAt = .now
                $0.licenseAcquired = $0.licenseAcquired || outcome.licenseAcquired
            }
            if revealOnCompletion {
                NSWorkspace.shared.activateFileViewerSelecting([outcome.fileURL])
            }
        } catch {
            let engineError = EngineError.wrap(error)
            if engineError.isCancellation || Task.isCancelled {
                removePartialFile(at: output == directory ? nil : output)
                update(id) { $0.state = .cancelled; $0.completedAt = .now; $0.progress = nil }
            } else {
                fail(id, engineError)
            }
        }
    }

    private func fail(_ id: UUID, _ error: EngineError) {
        update(id) {
            $0.state = .failed
            $0.completedAt = .now
            $0.progress = nil
            $0.failure = DownloadFailure(kind: error.kind, message: error.rawMessage, details: error.diagnostics)
        }
        if error.kind == .licenseRequired, let item = item(id: id), !item.request.acquireLicense {
            licensePrompt = item
        }
    }

    private func removePartialFile(at url: URL?) {
        guard let url else { return }
        let temporary = URL(fileURLWithPath: url.path + ".tmp")
        try? FileManager.default.removeItem(at: temporary)
    }

    private func persist() {
        guard let store else { return }
        persistTask?.cancel()
        let snapshot = items
        persistTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await store.save(snapshot)
        }
    }
}
