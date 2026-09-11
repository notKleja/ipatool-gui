import Foundation

enum DownloadState: String, Codable, Sendable, Hashable {
    case queued
    case preparing
    case acquiringLicense
    case downloading
    case completed
    case failed
    case cancelled

    var isActive: Bool {
        switch self {
        case .queued, .preparing, .acquiringLicense, .downloading: true
        case .completed, .failed, .cancelled: false
        }
    }

    var isTerminal: Bool { !isActive }

    var displayName: String {
        switch self {
        case .queued: "Waiting"
        case .preparing: "Preparing"
        case .acquiringLicense: "Acquiring License"
        case .downloading: "Downloading"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

/// Persisted description of a failure, safe to store (never contains secrets).
struct DownloadFailure: Codable, Sendable, Hashable {
    let kind: EngineErrorKind
    let message: String
    let details: String?
}

/// Everything needed to (re)start a download. Persisted with the history.
struct DownloadRequest: Codable, Sendable, Hashable {
    var appID: Int64
    var bundleID: String
    var appName: String
    var platform: AppPlatform
    var externalVersionID: ExternalVersionID?
    /// Version string as known before the download started; nil when unknown.
    var requestedVersion: String?
    var price: Double
    var acquireLicense: Bool
    var destinationDirectory: URL
    /// Full file path chosen by the user when resolving a filename conflict.
    var explicitDestination: URL?

    var isLatestVersion: Bool { externalVersionID == nil }
}

struct DownloadItem: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var request: DownloadRequest
    var state: DownloadState
    var destinationURL: URL?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var failure: DownloadFailure?
    /// 0…1 when ipatool reports byte progress; nil means indeterminate. Not persisted.
    var progress: Double?
    /// Whether ipatool reported that a license was acquired as part of the download.
    var licenseAcquired: Bool

    init(id: UUID = UUID(), request: DownloadRequest, state: DownloadState = .queued, createdAt: Date = .now) {
        self.id = id
        self.request = request
        self.state = state
        self.createdAt = createdAt
        self.licenseAcquired = false
    }

    private enum CodingKeys: String, CodingKey {
        case id, request, state, destinationURL, createdAt, startedAt, completedAt, failure, licenseAcquired
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        request = try c.decode(DownloadRequest.self, forKey: .request)
        let decodedState = try c.decode(DownloadState.self, forKey: .state)
        // Anything in flight when the app quit cannot be resumed; ipatool must start over.
        state = decodedState.isActive ? .cancelled : decodedState
        destinationURL = try c.decodeIfPresent(URL.self, forKey: .destinationURL)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        failure = try c.decodeIfPresent(DownloadFailure.self, forKey: .failure)
        licenseAcquired = try c.decodeIfPresent(Bool.self, forKey: .licenseAcquired) ?? false
        progress = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(request, forKey: .request)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(destinationURL, forKey: .destinationURL)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(failure, forKey: .failure)
        try c.encode(licenseAcquired, forKey: .licenseAcquired)
    }

    var appName: String { request.appName }
    var platform: AppPlatform { request.platform }

    var versionDescription: String {
        if let v = request.requestedVersion, !v.isEmpty { return v }
        return request.isLatestVersion ? "Latest" : "Historical build"
    }

    /// Whether the file ipatool wrote still exists on disk.
    var fileExists: Bool {
        guard let url = destinationURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
