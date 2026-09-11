import XCTest
@testable import IPAToolGUI

final class ErrorClassificationTests: XCTestCase {
    func testClassification() {
        let cases: [(String, EngineErrorKind)] = [
            ("license is required", .licenseRequired),
            ("failed to get account: The specified item could not be found in the keychain.", .notAuthenticated),
            ("auth code is required", .twoFactorRequired),
            ("Your Apple ID or password was entered incorrectly.", .invalidCredentials),
            ("password token is expired", .sessionExpired),
            ("purchasing paid apps is not supported", .paidAppNotSupported),
            ("app not found", .appNotFound),
            ("request failed: Get \"https://...\": dial tcp: lookup itunes.apple.com: no such host", .network),
            ("invalid response", .invalidResponse),
            ("could not find Info.plist", .versionUnavailable),
            ("failed to open file: open /x/y.ipa: permission denied", .outputNotWritable),
            ("write /x: no space left on device", .diskFull),
            ("item is temporarily unavailable", .temporarilyUnavailable),
            ("account is disabled", .accountDisabled),
            ("too many attempts", .tooManyAttempts),
            ("subscription required", .subscriptionRequired),
            ("", .unknown),
            ("gremlins", .unknown),
        ]
        for (message, expected) in cases {
            XCTAssertEqual(ErrorClassifier.classify(message: message), expected, message)
        }
    }

    func testErrorFromProcessResultPrefersJSONErrorField() {
        let result = ProcessResult(stdout: #"{"level":"error","error":"license is required","success":false}"#,
                                   stderr: "", exitCode: 1, wasTerminated: false, duration: 0.1, commandDescription: "ipatool download")
        let error = ErrorClassifier.error(fromResult: result)
        XCTAssertEqual(error.kind, .licenseRequired)
        XCTAssertEqual(error.rawMessage, "license is required")
        XCTAssertTrue(error.diagnostics?.contains("ipatool download") == true)
    }

    func testTerminatedProcessIsCancellation() {
        let result = ProcessResult(stdout: "", stderr: "", exitCode: 15, wasTerminated: true, duration: 0, commandDescription: "x")
        XCTAssertEqual(ErrorClassifier.error(fromResult: result).kind, .cancelled)
    }

    func testWrapMapsFoundationErrors() {
        XCTAssertEqual(EngineError.wrap(CancellationError()).kind, .cancelled)
        XCTAssertEqual(EngineError.wrap(URLError(.notConnectedToInternet)).kind, .network)
        XCTAssertEqual(EngineError.wrap(CocoaError(.fileWriteOutOfSpace)).kind, .diskFull)
    }
}

final class SecretRedactionTests: XCTestCase {
    func testKnownSecretsAreMasked() {
        let redactor = SecretRedactor(knownSecrets: ["hunter2"])
        XCTAssertEqual(redactor.redact("password is hunter2 ok"), "password is •••••• ok")
    }

    func testJSONSecretKeysAreMasked() {
        let redactor = SecretRedactor()
        let text = #"{"email":"a@b.c","passwordToken":"abc123","password":"pw"}"#
        let redacted = redactor.redact(text)
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("\"pw\""))
        XCTAssertTrue(redacted.contains("a@b.c"))
    }

    func testArgumentFlagsAreMasked() {
        let redactor = SecretRedactor()
        XCTAssertEqual(redactor.redact(arguments: ["--password", "x", "--auth-code=123456", "--email", "e"]),
                       ["--password", "••••••", "--auth-code=••••••", "--email", "e"])
        XCTAssertEqual(redactor.redact("ipatool auth login --password secret --auth-code 1234"),
                       "ipatool auth login --password •••••• --auth-code ••••••")
    }
}

final class FilenameSanitizerTests: XCTestCase {
    func testSanitizesForbiddenCharacters() {
        XCTAssertEqual(FilenameSanitizer.sanitize("A/B:C\\D?E*F\"G<H>I|J"), "A-B-C-D-E-F-G-H-I-J")
        XCTAssertEqual(FilenameSanitizer.sanitize("  .hidden  "), "hidden")
        XCTAssertEqual(FilenameSanitizer.sanitize(""), "App")
        XCTAssertEqual(FilenameSanitizer.sanitize(String(repeating: "x", count: 500)).count, 200)
    }

    func testPackageFilename() {
        XCTAssertEqual(FilenameSanitizer.packageFilename(appName: "WhatsApp Messenger", version: "24.18.77", platform: .iPhone, bundleID: "net.whatsapp.WhatsApp"),
                       "WhatsApp Messenger 24.18.77.ipa")
        XCTAssertEqual(FilenameSanitizer.packageFilename(appName: "Xcode", version: "16.0", platform: .mac, bundleID: "com.apple.dt.Xcode"),
                       "Xcode 16.0.pkg")
        XCTAssertEqual(FilenameSanitizer.packageFilename(appName: "", version: nil, platform: .iPad, bundleID: "com.x.y"), "com.x.y.ipa")
    }

    func testUniqueURL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("App 1.0.ipa")
        XCTAssertEqual(FilenameSanitizer.uniqueURL(for: url), url)
        try Data().write(to: url)
        XCTAssertEqual(FilenameSanitizer.uniqueURL(for: url).lastPathComponent, "App 1.0 (2).ipa")
        try Data().write(to: directory.appendingPathComponent("App 1.0 (2).ipa"))
        XCTAssertEqual(FilenameSanitizer.uniqueURL(for: url).lastPathComponent, "App 1.0 (3).ipa")
    }
}
