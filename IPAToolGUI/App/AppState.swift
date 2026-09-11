import Foundation
import Observation
import SwiftUI

enum EngineStatus: Sendable, Equatable {
    case detecting
    case ready(url: URL, version: IPAToolVersion)
    case unsupported(url: URL, version: IPAToolVersion)
    case invalid(url: URL, reason: String)
    case missing

    var isUsable: Bool {
        switch self {
        case .ready, .unsupported: true
        default: false
        }
    }

    var executable: URL? {
        switch self {
        case .ready(let url, _), .unsupported(let url, _), .invalid(let url, _): url
        default: nil
        }
    }

    var version: IPAToolVersion? {
        switch self {
        case .ready(_, let version), .unsupported(_, let version): version
        default: nil
        }
    }

    var statusText: String {
        switch self {
        case .detecting: "Detecting…"
        case .ready: "Ready"
        case .unsupported(_, let version): "ipatool \(version) is older than the supported \(IPAToolVersion.minimumSupported)"
        case .invalid(_, let reason): reason
        case .missing: "Not found"
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case discover, library, downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "Discover"
        case .library: "Library"
        case .downloads: "Downloads"
        }
    }

    var symbol: String {
        switch self {
        case .discover: "magnifyingglass"
        case .library: "square.grid.2x2"
        case .downloads: "arrow.down.circle"
        }
    }
}

struct DownloadConflict: Identifiable, Sendable {
    let id = UUID()
    let request: DownloadRequest
    let existingFile: URL
}

/// Root object wiring services to the UI. Lives for the app's lifetime.
@MainActor
@Observable
final class AppState {
    let settings: SettingsStore
    let diagnostics: DiagnosticLog
    let service: any IPAToolServing
    let auth: AuthenticationService
    let downloads: DownloadManager
    let metadata: any AppMetadataProviding
    let installer: EngineInstaller?

    private(set) var engine: EngineStatus = .detecting
    var selection: SidebarSection? = .discover
    var isSignInPresented = false
    var pendingConflict: DownloadConflict?
    var presentedError: EngineError?
    /// Incremented by the Focus Search command; Discover observes it.
    var searchFocusRequest = 0

    @ObservationIgnored private let locator: IPAToolLocator?
    @ObservationIgnored private let engineService: IPAToolService?
    @ObservationIgnored private var didStart = false

    init(settings: SettingsStore, diagnostics: DiagnosticLog, service: any IPAToolServing,
         locator: IPAToolLocator?, downloads: DownloadManager, metadata: any AppMetadataProviding,
         installer: EngineInstaller? = nil) {
        self.settings = settings
        self.installer = installer
        self.diagnostics = diagnostics
        self.service = service
        self.locator = locator
        self.engineService = service as? IPAToolService
        self.downloads = downloads
        self.metadata = metadata
        self.auth = AuthenticationService(service: service)
        downloads.maxConcurrent = settings.maxConcurrentDownloads
        downloads.revealOnCompletion = settings.revealAfterDownload
        downloads.conflictPolicy = settings.conflictPolicy
    }

    /// Production wiring.
    static func live() -> AppState {
        let settings = SettingsStore()
        let diagnostics = DiagnosticLog()
        let runner = ProcessRunner { entry in
            Task { @MainActor in diagnostics.record(entry) }
        }
        let service = IPAToolService(runner: runner, configuration: IPAToolConfiguration(executable: nil, verbose: settings.verboseLogging))
        let locator = IPAToolLocator(runner: runner)
        let downloads = DownloadManager(service: service, store: DownloadHistoryStore(), maxConcurrent: settings.maxConcurrentDownloads)
        let metadata = AppMetadataService {
            UserDefaults.standard.string(forKey: SettingsStore.Key.metadataCountry) ?? Locale.current.region?.identifier ?? "US"
        }
        return AppState(settings: settings, diagnostics: diagnostics, service: service, locator: locator,
                        downloads: downloads, metadata: metadata, installer: EngineInstaller(runner: runner))
    }

    /// Preview wiring with mocks; no processes, no network.
    static func preview(signedIn: Bool = true, engine: EngineStatus? = nil, mock: MockIPAToolService? = nil) -> AppState {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "previews.\(UUID().uuidString)") ?? .standard)
        let service = mock ?? (signedIn ? MockIPAToolService(fixture: .init(account: Fixtures.account)) : MockIPAToolService(fixture: .init(account: nil)))
        let downloads = DownloadManager(service: service, store: nil)
        let state = AppState(settings: settings, diagnostics: DiagnosticLog(), service: service, locator: nil,
                             downloads: downloads, metadata: MockAppMetadataService.previews)
        state.engine = engine ?? .ready(url: URL(fileURLWithPath: "/opt/homebrew/bin/ipatool"), version: .recommended)
        state.auth.didSignIn(Fixtures.account)
        if !signedIn { Task { await state.auth.refresh() } }
        return state
    }

    // MARK: - Lifecycle

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        await detectEngine()
    }

    func detectEngine() async {
        guard let locator else { return }
        engine = .detecting
        let outcome = await locator.detect(preferred: settings.customBinaryURL)
        apply(detection: outcome)
    }

    func selectBinary(_ url: URL) async {
        guard let locator else { return }
        engine = .detecting
        let outcome = await locator.validate(url)
        switch outcome {
        case .ready, .unsupported:
            settings.customBinaryPath = url.path
        case .invalid, .notFound:
            break
        }
        apply(detection: outcome)
    }

    private func apply(detection: EngineDetection) {
        switch detection {
        case .ready(let url, let version): engine = .ready(url: url, version: version)
        case .unsupported(let url, let version): engine = .unsupported(url: url, version: version)
        case .invalid(let url, let reason): engine = .invalid(url: url, reason: reason)
        case .notFound: engine = .missing
        }
        applyEngineConfiguration()
        if engine.isUsable {
            Task { await auth.refresh() }
        }
    }

    func applyEngineConfiguration() {
        engineService?.update(configuration: IPAToolConfiguration(executable: engine.executable, verbose: settings.verboseLogging))
        downloads.maxConcurrent = settings.maxConcurrentDownloads
        downloads.revealOnCompletion = settings.revealAfterDownload
        downloads.conflictPolicy = settings.conflictPolicy
    }

    var engineDescription: String {
        switch engine {
        case .ready(let url, let version), .unsupported(let url, let version): "ipatool \(version) at \(url.path)"
        case .invalid(let url, let reason): "\(url.path): \(reason)"
        case .missing: "not found"
        case .detecting: "detecting"
        }
    }

    // MARK: - Downloads

    /// Entry point for every "Download" button. Applies the conflict policy before queueing.
    func requestDownload(_ request: DownloadRequest) {
        var request = request
        request.destinationDirectory = settings.downloadDirectory
        if settings.conflictPolicy == .ask, let existing = DownloadManager.conflictingFile(for: request) {
            pendingConflict = DownloadConflict(request: request, existingFile: existing)
            return
        }
        downloads.enqueue(request)
        selection = .downloads
    }

    func resolveConflict(_ conflict: DownloadConflict, keepBoth: Bool) {
        var request = conflict.request
        if keepBoth {
            request.explicitDestination = FilenameSanitizer.uniqueURL(for: conflict.existingFile)
        } else {
            request.explicitDestination = conflict.existingFile
        }
        pendingConflict = nil
        downloads.enqueue(request)
        selection = .downloads
    }

    func makeDownloadRequest(app: AppStoreApp, platform: AppPlatform, version: AppVersion? = nil, acquireLicense: Bool = false) -> DownloadRequest {
        DownloadRequest(appID: app.id, bundleID: app.bundleID, appName: app.displayName, platform: platform,
                        externalVersionID: version?.externalID,
                        requestedVersion: version?.displayVersion ?? (app.version.isEmpty ? nil : app.version),
                        price: app.price, acquireLicense: acquireLicense,
                        destinationDirectory: settings.downloadDirectory)
    }

    func present(_ error: any Error) {
        let engineError = EngineError.wrap(error)
        guard !engineError.isCancellation else { return }
        if engineError.kind == .notAuthenticated || engineError.kind == .sessionExpired {
            auth.noteSessionExpired()
        }
        presentedError = engineError
    }
}
