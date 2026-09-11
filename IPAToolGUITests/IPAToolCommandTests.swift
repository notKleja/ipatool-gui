import XCTest
@testable import IPAToolGUI

final class IPAToolCommandTests: XCTestCase {
    func testSearchArguments() {
        let command = IPAToolCommands.search(term: "-weird term", limit: 25, platform: .iPad)
        XCTAssertEqual(command.arguments, ["search", "--limit", "25", "--platform", "ipad", "--format", "json", "--non-interactive", "--", "-weird term"])
        XCTAssertEqual(command.standardInput, .none)
    }

    func testSearchClampsVisionLimit() {
        let command = IPAToolCommands.search(term: "x", limit: 50, platform: .vision)
        XCTAssertTrue(command.arguments.contains("12"))
    }

    func testLoginUsesPseudoTerminalAndNoPasswordFlag() {
        let command = IPAToolCommands.authLogin(email: "me@example.com")
        XCTAssertEqual(command.arguments, ["auth", "login", "--email", "me@example.com", "--format", "json"])
        XCTAssertEqual(command.standardInput, .pseudoTerminal)
        XCTAssertFalse(command.arguments.contains("--password"))
        XCTAssertFalse(command.arguments.contains("--non-interactive"))
    }

    func testAuthInfoAndRevoke() {
        XCTAssertEqual(IPAToolCommands.authInfo().arguments, ["auth", "info", "--format", "json", "--non-interactive"])
        XCTAssertEqual(IPAToolCommands.authRevoke(verbose: true).arguments, ["auth", "revoke", "--format", "json", "--verbose", "--non-interactive"])
    }

    func testPurchaseArguments() {
        XCTAssertEqual(IPAToolCommands.purchase(bundleID: "com.x.y", platform: .mac).arguments,
                       ["purchase", "--bundle-identifier", "com.x.y", "--platform", "macos", "--format", "json", "--non-interactive"])
    }

    func testListPurchasesClampsPageSize() {
        let command = IPAToolCommands.listPurchases(page: 0, maxResults: 500)
        XCTAssertEqual(command.arguments, ["list-purchases", "--page", "1", "--max-results", "100", "--format", "json", "--non-interactive"])
    }

    func testVersionCommands() {
        XCTAssertEqual(IPAToolCommands.listVersions(appID: 42).arguments, ["list-versions", "--app-id", "42", "--format", "json", "--non-interactive"])
        XCTAssertEqual(IPAToolCommands.versionMetadata(appID: 42, externalVersionID: ExternalVersionID("999")).arguments,
                       ["get-version-metadata", "--app-id", "42", "--external-version-id", "999", "--format", "json", "--non-interactive"])
    }

    func testDownloadLatestIsInteractiveWithoutExternalVersion() {
        let output = URL(fileURLWithPath: "/tmp/App 1.0.ipa")
        let command = IPAToolCommands.download(appID: 7, platform: .iPhone, output: output, externalVersionID: nil, acquireLicense: false)
        XCTAssertEqual(command.arguments, ["download", "--app-id", "7", "--platform", "iphone", "--output", "/tmp/App 1.0.ipa", "--format", "json"])
        XCTAssertTrue(command.interactive)
    }

    func testDownloadHistoricalWithPurchase() {
        let output = URL(fileURLWithPath: "/tmp/dir")
        let command = IPAToolCommands.download(appID: 7, platform: .appleTV, output: output, externalVersionID: ExternalVersionID("123"), acquireLicense: true)
        XCTAssertEqual(command.arguments, ["download", "--app-id", "7", "--platform", "appletv", "--output", "/tmp/dir", "--external-version-id", "123", "--purchase", "--format", "json"])
    }

    func testVersionParsing() {
        XCTAssertEqual(IPAToolVersion(parsing: "ipatool version 2.5.0\n")?.description, "2.5.0")
        XCTAssertEqual(IPAToolVersion(parsing: "v2.4.0-rc.1")?.description, "2.4.0")
        XCTAssertNil(IPAToolVersion(parsing: "not a version"))
        XCTAssertTrue(IPAToolVersion(parsing: "2.5.0")!.isSupported)
        XCTAssertFalse(IPAToolVersion(parsing: "1.1.4")!.isSupported)
        XCTAssertFalse(IPAToolVersion(parsing: "2.3.0")!.isRecommendedOrNewer)
    }
}
