import Foundation
import os

/// In-memory stand-in for previews and tests. Never touches the App Store.
final class MockIPAToolService: IPAToolServing, Sendable {
    struct Fixture: Sendable {
        var version = IPAToolVersion(major: 2, minor: 5, patch: 0, raw: "ipatool version 2.5.0")
        var account: Account?
        var requiresTwoFactor = false
        var searchResults: [AppStoreApp] = Fixtures.searchResults
        var purchases: [AppStoreApp] = Fixtures.purchases
        var versions: [AppVersion] = Fixtures.versions
        var downloadError: EngineError?
        var downloadDelay: Duration = .milliseconds(600)
        var metadataDelay: Duration = .milliseconds(150)
        var reportsProgress = true
    }

    private let state: OSAllocatedUnfairLock<Fixture>
    private let downloadedFiles = OSAllocatedUnfairLock(initialState: [URL]())

    init(fixture: Fixture = Fixture()) {
        state = OSAllocatedUnfairLock(initialState: fixture)
    }

    static let signedOut = MockIPAToolService(fixture: Fixture(account: nil))
    static let signedIn = MockIPAToolService(fixture: Fixture(account: Fixtures.account))

    var fixture: Fixture { state.withLock { $0 } }
    func update(_ body: @Sendable (inout Fixture) -> Void) { state.withLock(body) }

    func version() async throws -> IPAToolVersion { fixture.version }

    func accountInfo() async throws -> Account? { fixture.account }

    func beginLogin(email: String, password: String) -> any LoginAttempt {
        MockLoginAttempt(service: self, email: email, requiresTwoFactor: fixture.requiresTwoFactor, passwordEmpty: password.isEmpty)
    }

    func revokeAuthentication() async throws {
        update { $0.account = nil }
    }

    func search(term: String, limit: Int, platform: AppPlatform) async throws -> [AppStoreApp] {
        guard fixture.account != nil else { throw EngineError(kind: .notAuthenticated) }
        try await Task.sleep(for: .milliseconds(200))
        let lower = term.lowercased()
        return Array(fixture.searchResults.filter { lower.isEmpty || $0.name.lowercased().contains(lower) || $0.bundleID.lowercased().contains(lower) }.prefix(limit))
    }

    func purchasedApps(page: Int, pageSize: Int) async throws -> PurchasedPage {
        guard fixture.account != nil else { throw EngineError(kind: .notAuthenticated) }
        try await Task.sleep(for: .milliseconds(200))
        let all = fixture.purchases
        let start = (page - 1) * pageSize
        let slice = start < all.count ? Array(all[start..<min(all.count, start + pageSize)]) : []
        return PurchasedPage(apps: slice, page: page, count: slice.count, totalCount: all.count)
    }

    func acquireLicense(bundleID: String, platform: AppPlatform) async throws -> LicenseResult {
        try await Task.sleep(for: .milliseconds(300))
        return LicenseResult(alreadyOwned: false)
    }

    func versions(appID: Int64) async throws -> [ExternalVersionID] {
        try await Task.sleep(for: .milliseconds(200))
        return fixture.versions.map(\.externalID)
    }

    func versionMetadata(appID: Int64, externalVersionID: ExternalVersionID) async throws -> AppVersion {
        try await Task.sleep(for: fixture.metadataDelay)
        guard let version = fixture.versions.first(where: { $0.externalID == externalVersionID }) else {
            throw EngineError(kind: .versionUnavailable)
        }
        return version
    }

    func download(appID: Int64, platform: AppPlatform, output: URL, externalVersionID: ExternalVersionID?,
                  acquireLicense: Bool, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> DownloadOutcome {
        let fixture = fixture
        if let error = fixture.downloadError { throw error }
        let steps = 10
        for step in 1...steps {
            try Task.checkCancellation()
            try await Task.sleep(for: fixture.downloadDelay / steps)
            if fixture.reportsProgress { progress(DownloadProgress(fraction: Double(step) / Double(steps))) }
        }
        let isDirectory = (try? output.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let destination = isDirectory ? output.appendingPathComponent("mock_\(appID).\(platform.packageExtension)") : output
        downloadedFiles.withLock { $0.append(destination) }
        return DownloadOutcome(fileURL: destination, licenseAcquired: acquireLicense)
    }
}

final class MockLoginAttempt: LoginAttempt, Sendable {
    private let service: MockIPAToolService
    private let email: String
    private let requiresTwoFactor: Bool
    private let passwordEmpty: Bool

    init(service: MockIPAToolService, email: String, requiresTwoFactor: Bool, passwordEmpty: Bool) {
        self.service = service
        self.email = email
        self.requiresTwoFactor = requiresTwoFactor
        self.passwordEmpty = passwordEmpty
    }

    func start() async throws -> LoginOutcome {
        try await Task.sleep(for: .milliseconds(400))
        if passwordEmpty { throw EngineError(kind: .invalidCredentials, rawMessage: "Your Apple ID or password was entered incorrectly.") }
        if requiresTwoFactor { return .verificationRequired }
        return .signedIn(signIn())
    }

    func submitVerificationCode(_ code: String) async throws -> Account {
        try await Task.sleep(for: .milliseconds(400))
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw EngineError(kind: .invalidCredentials, rawMessage: "Verification code rejected")
        }
        return signIn()
    }

    func cancel() {}

    private func signIn() -> Account {
        let account = Account(name: "Preview User", email: email)
        service.update { $0.account = account }
        return account
    }
}

/// Shared preview/test data.
enum Fixtures {
    static let account = Account(name: "Omar Example", email: "omar@example.com")

    static let searchResults: [AppStoreApp] = [
        AppStoreApp(id: 284882215, bundleID: "com.facebook.Facebook", name: "Facebook", version: "480.0", price: 0),
        AppStoreApp(id: 389801252, bundleID: "com.burbn.instagram", name: "Instagram", version: "352.0", price: 0),
        AppStoreApp(id: 310633997, bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp Messenger", version: "24.18.77", price: 0),
        AppStoreApp(id: 1017146519, bundleID: "com.nintendo.zaka", name: "Pocket Camp", version: "5.6.1", price: 0),
        AppStoreApp(id: 1064216828, bundleID: "com.ustwo.monumentvalley2", name: "Monument Valley 2", version: "3.4.5", price: 4.99),
    ]

    static let purchases: [AppStoreApp] = [
        AppStoreApp(id: 310633997, bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp Messenger", version: "24.18.77", price: 0,
                    purchaseDate: Date(timeIntervalSince1970: 1_756_000_000)),
        AppStoreApp(id: 389801252, bundleID: "com.burbn.instagram", name: "Instagram", version: "352.0", price: 0,
                    purchaseDate: Date(timeIntervalSince1970: 1_720_000_000)),
        AppStoreApp(id: 1064216828, bundleID: "com.ustwo.monumentvalley2", name: "Monument Valley 2", version: "3.4.5", price: 4.99,
                    purchaseDate: Date(timeIntervalSince1970: 1_690_000_000)),
    ]

    static let versions: [AppVersion] = [
        AppVersion(externalID: ExternalVersionID("870114231"), displayVersion: "7.4.1", releaseDate: Date(timeIntervalSince1970: 1_786_996_800)),
        AppVersion(externalID: ExternalVersionID("869012345"), displayVersion: "7.4.0", releaseDate: Date(timeIntervalSince1970: 1_785_700_800)),
        AppVersion(externalID: ExternalVersionID("867654321"), displayVersion: "7.3.2", releaseDate: Date(timeIntervalSince1970: 1_784_577_600)),
        AppVersion(externalID: ExternalVersionID("865000000"), displayVersion: "7.3.1", releaseDate: Date(timeIntervalSince1970: 1_782_000_000)),
    ]

    static func downloadRequest(app: AppStoreApp = searchResults[0], platform: AppPlatform = .iPhone) -> DownloadRequest {
        DownloadRequest(appID: app.id, bundleID: app.bundleID, appName: app.name, platform: platform,
                        externalVersionID: nil, requestedVersion: app.version, price: app.price,
                        acquireLicense: false, destinationDirectory: FileManager.default.temporaryDirectory)
    }

    static var activeDownload: DownloadItem {
        var item = DownloadItem(request: downloadRequest(), state: .downloading)
        item.progress = 0.42
        item.startedAt = .now
        return item
    }

    static var failedDownload: DownloadItem {
        var item = DownloadItem(request: downloadRequest(app: searchResults[1]), state: .failed)
        item.failure = DownloadFailure(kind: .licenseRequired, message: "license is required", details: "$ ipatool download …\nexit: 1")
        return item
    }

    static var completedDownload: DownloadItem {
        var item = DownloadItem(request: downloadRequest(app: searchResults[2]), state: .completed)
        item.destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent("WhatsApp Messenger 24.18.77.ipa")
        item.completedAt = .now
        return item
    }
}
