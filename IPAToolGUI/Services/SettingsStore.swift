import Foundation
import Observation

enum FileConflictPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    case ask
    case uniqueName

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ask: "Ask what to do"
        case .uniqueName: "Keep both (add a number)"
        }
    }
}

/// Non-sensitive preferences backed by UserDefaults. Secrets never go here.
@MainActor
@Observable
final class SettingsStore {
    enum Key {
        static let downloadDirectory = "downloadDirectory"
        static let revealAfterDownload = "revealAfterDownload"
        static let defaultPlatform = "defaultPlatform"
        static let maxConcurrentDownloads = "maxConcurrentDownloads"
        static let customBinaryPath = "customBinaryPath"
        static let verboseLogging = "verboseLogging"
        static let conflictPolicy = "conflictPolicy"
        static let metadataCountry = "metadataCountry"
        static let metadataEnabled = "metadataEnabled"
        static let searchLimit = "searchLimit"
        static let showRawDiagnostics = "showRawDiagnostics"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var downloadDirectory: URL { didSet { defaults.set(downloadDirectory.path, forKey: Key.downloadDirectory) } }
    var revealAfterDownload: Bool { didSet { defaults.set(revealAfterDownload, forKey: Key.revealAfterDownload) } }
    var defaultPlatform: AppPlatform { didSet { defaults.set(defaultPlatform.rawValue, forKey: Key.defaultPlatform) } }
    var maxConcurrentDownloads: Int { didSet { defaults.set(maxConcurrentDownloads, forKey: Key.maxConcurrentDownloads) } }
    var customBinaryPath: String? { didSet { defaults.set(customBinaryPath, forKey: Key.customBinaryPath) } }
    var verboseLogging: Bool { didSet { defaults.set(verboseLogging, forKey: Key.verboseLogging) } }
    var conflictPolicy: FileConflictPolicy { didSet { defaults.set(conflictPolicy.rawValue, forKey: Key.conflictPolicy) } }
    var metadataCountry: String { didSet { defaults.set(metadataCountry, forKey: Key.metadataCountry) } }
    var metadataEnabled: Bool { didSet { defaults.set(metadataEnabled, forKey: Key.metadataEnabled) } }
    var searchLimit: Int { didSet { defaults.set(searchLimit, forKey: Key.searchLimit) } }
    var showRawDiagnostics: Bool { didSet { defaults.set(showRawDiagnostics, forKey: Key.showRawDiagnostics) } }

    static var defaultDownloadDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        downloadDirectory = defaults.string(forKey: Key.downloadDirectory).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.defaultDownloadDirectory
        revealAfterDownload = defaults.object(forKey: Key.revealAfterDownload) as? Bool ?? false
        defaultPlatform = defaults.string(forKey: Key.defaultPlatform).flatMap(AppPlatform.init(rawValue:)) ?? .iPhone
        let concurrency = defaults.integer(forKey: Key.maxConcurrentDownloads)
        maxConcurrentDownloads = (1...4).contains(concurrency) ? concurrency : 1
        customBinaryPath = defaults.string(forKey: Key.customBinaryPath)
        verboseLogging = defaults.bool(forKey: Key.verboseLogging)
        conflictPolicy = defaults.string(forKey: Key.conflictPolicy).flatMap(FileConflictPolicy.init(rawValue:)) ?? .ask
        metadataCountry = defaults.string(forKey: Key.metadataCountry) ?? (Locale.current.region?.identifier ?? "US")
        metadataEnabled = defaults.object(forKey: Key.metadataEnabled) as? Bool ?? true
        let limit = defaults.integer(forKey: Key.searchLimit)
        searchLimit = (5...100).contains(limit) ? limit : 25
        showRawDiagnostics = defaults.bool(forKey: Key.showRawDiagnostics)
    }

    var customBinaryURL: URL? {
        guard let customBinaryPath, !customBinaryPath.isEmpty else { return nil }
        return URL(fileURLWithPath: customBinaryPath)
    }
}
