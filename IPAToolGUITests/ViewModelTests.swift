import XCTest
@testable import IPAToolGUI

@MainActor
final class DownloadManagerTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitUntil(_ timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline { XCTFail("timed out"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testSuccessfulDownloadTransitionsToCompleted() async throws {
        let mock = MockIPAToolService(fixture: .init(account: Fixtures.account, downloadDelay: .milliseconds(100)))
        let manager = DownloadManager(service: mock, store: nil)
        var request = Fixtures.downloadRequest()
        request.destinationDirectory = try makeDirectory()
        let item = manager.enqueue(request)
        XCTAssertEqual(manager.item(id: item.id)?.state, .queued)
        try await waitUntil { manager.item(id: item.id)?.state == .completed }
        let finished = try XCTUnwrap(manager.item(id: item.id))
        XCTAssertEqual(finished.destinationURL?.lastPathComponent, "Facebook 480.0.ipa")
        XCTAssertEqual(finished.progress, 1)
        XCTAssertNotNil(finished.completedAt)
    }

    func testFailedDownloadRecordsFailureAndLicensePrompt() async throws {
        let mock = MockIPAToolService(fixture: .init(account: Fixtures.account,
                                                     downloadError: EngineError(kind: .licenseRequired, rawMessage: "license is required")))
        let manager = DownloadManager(service: mock, store: nil)
        var request = Fixtures.downloadRequest()
        request.destinationDirectory = try makeDirectory()
        let item = manager.enqueue(request)
        try await waitUntil { manager.item(id: item.id)?.state == .failed }
        XCTAssertEqual(manager.item(id: item.id)?.failure?.kind, .licenseRequired)
        XCTAssertEqual(manager.licensePrompt?.id, item.id)

        manager.retry(id: item.id, acquireLicense: true)
        XCTAssertNil(manager.item(id: item.id))
        let retried = try XCTUnwrap(manager.items.first)
        XCTAssertTrue(retried.request.acquireLicense)
        try await waitUntil { manager.items.first?.state == .failed }
    }

    func testCancellationTransitionsToCancelled() async throws {
        let mock = MockIPAToolService(fixture: .init(account: Fixtures.account, downloadDelay: .seconds(5)))
        let manager = DownloadManager(service: mock, store: nil)
        var request = Fixtures.downloadRequest()
        request.destinationDirectory = try makeDirectory()
        let item = manager.enqueue(request)
        try await waitUntil { manager.item(id: item.id)?.state == .downloading }
        manager.cancel(id: item.id)
        try await waitUntil { manager.item(id: item.id)?.state == .cancelled }
        XCTAssertTrue(manager.activeItems.isEmpty)
    }

    func testConcurrencyIsBounded() async throws {
        let mock = MockIPAToolService(fixture: .init(account: Fixtures.account, downloadDelay: .milliseconds(300)))
        let manager = DownloadManager(service: mock, store: nil, maxConcurrent: 1)
        var request = Fixtures.downloadRequest()
        request.destinationDirectory = try makeDirectory()
        let first = manager.enqueue(request)
        let second = manager.enqueue(Fixtures.downloadRequest(app: Fixtures.searchResults[1]))
        try await waitUntil { manager.item(id: first.id)?.state == .downloading }
        XCTAssertEqual(manager.item(id: second.id)?.state, .queued)
        try await waitUntil { manager.item(id: first.id)?.state == .completed }
        try await waitUntil { manager.item(id: second.id)?.state != .queued }
    }

    func testUnwritableDirectoryFailsWithoutInvokingEngine() async throws {
        let mock = MockIPAToolService(fixture: .init(account: Fixtures.account))
        let manager = DownloadManager(service: mock, store: nil)
        var request = Fixtures.downloadRequest()
        request.destinationDirectory = URL(fileURLWithPath: "/System/Library/NotWritable-\(UUID().uuidString)")
        let item = manager.enqueue(request)
        try await waitUntil { manager.item(id: item.id)?.state == .failed }
        XCTAssertEqual(manager.item(id: item.id)?.failure?.kind, .outputNotWritable)
    }

    func testRemoveKeepsFileOnDisk() async throws {
        let mock = MockIPAToolService(fixture: .init(account: Fixtures.account, downloadDelay: .milliseconds(50)))
        let manager = DownloadManager(service: mock, store: nil)
        var request = Fixtures.downloadRequest()
        request.destinationDirectory = try makeDirectory()
        let item = manager.enqueue(request)
        try await waitUntil { manager.item(id: item.id)?.state == .completed }
        let url = try XCTUnwrap(manager.item(id: item.id)?.destinationURL)
        try Data("x".utf8).write(to: url)
        manager.remove(id: item.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(manager.items.isEmpty)
    }

    func testHistoryPersistsAndInFlightItemsBecomeCancelled() async throws {
        let file = try makeDirectory().appendingPathComponent("downloads.json")
        let store = DownloadHistoryStore(fileURL: file)
        var active = DownloadItem(request: Fixtures.downloadRequest(), state: .downloading)
        active.progress = 0.5
        var done = DownloadItem(request: Fixtures.downloadRequest(app: Fixtures.searchResults[1]), state: .completed)
        done.destinationURL = URL(fileURLWithPath: "/tmp/x.ipa")
        await store.save([active, done])
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.first { $0.id == active.id }?.state, .cancelled)
        XCTAssertNil(loaded.first { $0.id == active.id }?.progress)
        XCTAssertEqual(loaded.first { $0.id == done.id }?.destinationURL?.path, "/tmp/x.ipa")
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(contents.contains("password"))
    }

    func testDownloadStateFlags() {
        XCTAssertTrue(DownloadState.queued.isActive)
        XCTAssertTrue(DownloadState.acquiringLicense.isActive)
        XCTAssertTrue(DownloadState.completed.isTerminal)
        XCTAssertTrue(DownloadState.failed.isTerminal)
        XCTAssertTrue(DownloadState.cancelled.isTerminal)
    }
}

@MainActor
final class ViewModelTests: XCTestCase {
    private func waitUntil(_ timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline { XCTFail("timed out"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testDiscoverDebouncesAndSearches() async throws {
        let mock = MockIPAToolService(fixture: .init(account: Fixtures.account))
        let model = DiscoverViewModel(service: mock, metadata: MockAppMetadataService(), platform: .iPhone, limit: { 10 }, debounce: .milliseconds(50))
        model.query = "insta"
        XCTAssertTrue(model.results.isEmpty)
        try await waitUntil { !model.results.isEmpty }
        XCTAssertEqual(model.results.map(\.name), ["Instagram"])
        model.query = ""
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertFalse(model.hasSearched)
    }

    func testDiscoverSurfacesNotAuthenticated() async throws {
        let mock = MockIPAToolService(fixture: .init(account: nil))
        let model = DiscoverViewModel(service: mock, metadata: MockAppMetadataService(), platform: .iPhone, limit: { 10 }, debounce: .milliseconds(10))
        model.query = "x"
        try await waitUntil { model.error != nil }
        XCTAssertEqual(model.error?.kind, .notAuthenticated)
    }

    func testLibraryPaginates() async throws {
        let mock = MockIPAToolService(fixture: .init(account: Fixtures.account))
        let model = LibraryViewModel(service: mock, metadata: MockAppMetadataService(), pageSize: 2)
        model.refresh()
        try await waitUntil { model.apps.count == 2 }
        XCTAssertTrue(model.hasMore)
        XCTAssertEqual(model.totalCount, 3)
        model.loadMore()
        try await waitUntil { model.apps.count == 3 }
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(model.filteredApps.first?.name, "WhatsApp Messenger", "newest acquisition first")
        model.filter = "monument"
        XCTAssertEqual(model.filteredApps.count, 1)
    }

    func testVersionHistoryResolvesWithBoundedConcurrency() async throws {
        let mock = MockIPAToolService(fixture: .init(account: Fixtures.account, metadataDelay: .milliseconds(30)))
        let model = VersionHistoryViewModel(service: mock, appID: 1, maxConcurrentLookups: 2)
        model.load()
        try await waitUntil { model.rows.count == 4 && !model.isResolving }
        XCTAssertEqual(model.sortedRows.map(\.displayVersion), ["7.4.1", "7.4.0", "7.3.2", "7.3.1"])
        XCTAssertEqual(model.resolvedCount, 4)
    }

    func testSignInFlowWithTwoFactor() async throws {
        let mock = MockIPAToolService(fixture: .init(account: nil, requiresTwoFactor: true))
        let auth = AuthenticationService(service: mock)
        let model = SignInViewModel(auth: auth)
        model.email = "me@example.com"
        model.password = "pw"
        model.submitCredentials()
        XCTAssertEqual(model.password, "", "password must be dropped immediately")
        try await waitUntil { model.step == .verification }
        model.verificationCode = "123456"
        model.submitVerificationCode()
        try await waitUntil { model.signedInAccount != nil }
        XCTAssertEqual(auth.account?.email, "me@example.com")
        XCTAssertEqual(model.verificationCode, "")
    }

    func testSignInFailureReturnsToCredentials() async throws {
        let mock = MockIPAToolService(fixture: .init(account: nil, requiresTwoFactor: true))
        let model = SignInViewModel(auth: AuthenticationService(service: mock))
        model.email = "me@example.com"
        model.password = "pw"
        model.submitCredentials()
        try await waitUntil { model.step == .verification }
        model.verificationCode = "0000"
        model.submitVerificationCode()
        try await waitUntil { model.error != nil }
        XCTAssertEqual(model.step, .credentials)
    }

    func testAuthenticationRefreshAndSignOut() async throws {
        let mock = MockIPAToolService(fixture: .init(account: Fixtures.account))
        let auth = AuthenticationService(service: mock)
        await auth.refresh()
        XCTAssertEqual(auth.account, Fixtures.account)
        try await auth.signOut()
        XCTAssertFalse(auth.isSignedIn)
        await auth.refresh()
        XCTAssertEqual(auth.state, .signedOut)
    }
}
