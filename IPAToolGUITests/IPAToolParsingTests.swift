import XCTest
@testable import IPAToolGUI

final class IPAToolParsingTests: XCTestCase {
    func testSearchResponseDecoding() throws {
        let output = """
        {"level":"debug","time":"2026-09-11T10:00:00Z","message":"noise"}
        {"level":"info","time":"2026-09-11T10:00:01Z","count":2,"apps":[{"id":284882215,"bundleID":"com.facebook.Facebook","name":"Facebook","version":"480.0","price":0,"newField":true},{"id":1064216828,"bundleID":"com.ustwo.monumentvalley2","name":"Monument Valley 2","version":"3.4.5","price":4.99}]}
        """
        let response = try IPAToolOutput.decodeResult(SearchResponse.self, from: output)
        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.apps.first?.bundleID, "com.facebook.Facebook")
        XCTAssertTrue(response.apps[0].isFree)
        XCTAssertFalse(response.apps[1].isFree)
        XCTAssertNil(response.apps[0].purchaseDate)
    }

    func testAuthInfoDecoding() throws {
        let output = #"{"level":"info","time":"2026-09-11T10:00:00Z","name":"Omar Example","email":"omar@example.com","success":true}"#
        let account = try IPAToolOutput.decodeResult(Account.self, from: output)
        XCTAssertEqual(account, Account(name: "Omar Example", email: "omar@example.com"))
    }

    func testListVersionsDecoding() throws {
        let output = #"{"level":"info","externalVersionIdentifiers":["870114231","869012345"],"bundleID":"com.x.y","success":true}"#
        let response = try IPAToolOutput.decodeResult(ListVersionsResponse.self, from: output)
        XCTAssertEqual(response.externalVersionIdentifiers.map(\.rawValue), ["870114231", "869012345"])
        XCTAssertEqual(response.bundleID, "com.x.y")
        XCTAssertTrue(ExternalVersionID("870114231") > ExternalVersionID("869012345"))
    }

    func testVersionMetadataDecoding() throws {
        let output = #"{"level":"info","time":"2026-09-11T10:00:00Z","externalVersionID":"870114231","displayVersion":"7.4.1","releaseDate":"2026-08-18T14:00:00Z","success":true}"#
        let version = try IPAToolOutput.decodeResult(AppVersion.self, from: output)
        XCTAssertEqual(version.displayVersion, "7.4.1")
        XCTAssertEqual(version.externalID.rawValue, "870114231")
        XCTAssertEqual(version.releaseDate, DateParsing.parse("2026-08-18T14:00:00Z"))
    }

    func testPurchasedAppsDecoding() throws {
        let output = #"{"level":"info","count":1,"totalCount":57,"page":2,"apps":[{"id":310633997,"bundleID":"net.whatsapp.WhatsApp","name":"WhatsApp Messenger","version":"24.18.77","price":0,"purchaseDate":"2025-08-24T01:46:40Z"}]}"#
        let page = try IPAToolOutput.decodeResult(PurchasedPage.self, from: output)
        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalCount, 57)
        XCTAssertNotNil(page.apps.first?.purchaseDate)
        XCTAssertTrue(page.hasMore(pageSize: 25))
        XCTAssertFalse(PurchasedPage(apps: page.apps, page: 3, count: 1, totalCount: 57).hasMore(pageSize: 25))
    }

    func testResultLineSkipsMessagesAndProgress() {
        let output = """
        {"level":"info","message":"preparing"}
        downloading  45% |████      | (12/27 MB, 3.2 MB/s)
        {"level":"info","output":"/tmp/x.ipa","purchased":false,"success":true}
        """
        XCTAssertEqual(IPAToolOutput.resultLine(in: output), #"{"level":"info","output":"/tmp/x.ipa","purchased":false,"success":true}"#)
    }

    func testErrorMessageExtraction() {
        let output = #"{"level":"error","error":"license is required","success":false}"#
        XCTAssertEqual(IPAToolOutput.errorMessage(in: output), "license is required")
    }

    func testProgressFraction() {
        XCTAssertEqual(IPAToolOutput.progressFraction(in: "downloading  45% |████      | (12/27 MB, 3.2 MB/s)"), 0.45)
        XCTAssertNil(IPAToolOutput.progressFraction(in: "downloading"))
        XCTAssertNil(IPAToolOutput.progressFraction(in: "999%"))
    }

    func testLineAccumulatorSplitsOnCarriageReturn() {
        let accumulator = LineAccumulator()
        XCTAssertEqual(accumulator.append("a 10%\rb 20%\rpartial"), ["a 10%", "b 20%"])
        XCTAssertEqual(accumulator.append(" line\n"), ["partial line"])
        XCTAssertNil(accumulator.flush())
    }

    func testMetadataLookupDecodingIsLenient() throws {
        let json = #"{"resultCount":2,"results":[{"trackId":1,"artistName":"Dev","artworkUrl512":"https://example.com/a.png","fileSizeBytes":"12345","screenshotUrls":[]},{"bogus":true}]}"#
        let response = try JSONDecoder().decode(LookupResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results.first?.fileSizeBytes, 12345)
        XCTAssertEqual(response.results.first?.developerName, "Dev")
    }
}
