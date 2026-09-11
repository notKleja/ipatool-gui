import XCTest
@testable import IPAToolGUI

/// Drives the real `IPAToolService` against a shell script that speaks ipatool's stdout protocol
/// (JSON lines, TTY password prompt, stdin 2FA prompt, `\r`-separated progress bar).
final class FakeEngineIntegrationTests: XCTestCase {
    private static let script = #"""
    #!/bin/sh
    case "$1" in
      --version) echo "ipatool version 2.5.0"; exit 0;;
      auth)
        case "$2" in
          login)
            [ -t 0 ] || { echo '{"level":"error","error":"failed to read password: inappropriate ioctl for device","success":false}'; exit 1; }
            echo '{"level":"info","message":"enter password:"}'
            read pw
            echo '{"level":"info","message":"preparing authentication; the first login may take a few minutes"}'
            if [ "$pw" != "correct-horse" ]; then
              echo '{"level":"error","error":"Your Apple ID or password was entered incorrectly.","success":false}'; exit 1
            fi
            echo '{"level":"info","message":"enter 2FA code:"}'
            read code
            if [ "$code" != "123456" ]; then
              echo '{"level":"error","error":"something went wrong","success":false}'; exit 1
            fi
            echo '{"level":"info","name":"Test User","email":"'"$4"'","success":true}'
            ;;
          info)
            if [ -n "$FAKE_SIGNED_OUT" ]; then
              echo '{"level":"error","error":"failed to get account: The specified item could not be found in the keychain.","success":false}'; exit 1
            fi
            echo '{"level":"info","name":"Test User","email":"t@example.com","success":true}'
            ;;
          revoke) echo '{"level":"info","success":true}';;
        esac;;
      search)
        echo '{"level":"info","count":1,"apps":[{"id":1,"bundleID":"com.example.app","name":"Example","version":"1.0","price":0}]}';;
      download)
        out=""
        while [ $# -gt 0 ]; do if [ "$1" = "--output" ]; then out="$2"; fi; shift; done
        printf 'downloading  10%% |█         | (1/10 MB, 1.0 MB/s)\r'
        printf 'downloading  55%% |█████     | (5/10 MB, 1.0 MB/s)\r'
        printf '                                                     \r'
        echo "payload" > "$out"
        echo '{"level":"info","output":"'"$out"'","purchased":true,"success":true}'
        ;;
      *) echo '{"level":"error","error":"unknown command","success":false}'; exit 1;;
    esac
    """#

    private var scriptURL: URL!
    private var service: IPAToolService!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        scriptURL = directory.appendingPathComponent("ipatool")
        try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        service = IPAToolService(runner: ProcessRunner(), configuration: IPAToolConfiguration(executable: scriptURL))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
    }

    func testVersionAndLocatorValidation() async throws {
        let version = try await service.version()
        XCTAssertEqual(version.description, "2.5.0")
        let locator = IPAToolLocator(runner: ProcessRunner())
        let detection = await locator.validate(scriptURL)
        XCTAssertEqual(detection, .ready(url: scriptURL, version: version))
        let missing = await locator.validate(URL(fileURLWithPath: "/nonexistent/ipatool"))
        XCTAssertEqual(missing, .notFound)
    }

    func testAccountInfoSignedIn() async throws {
        let account = try await service.accountInfo()
        XCTAssertEqual(account?.email, "t@example.com")
    }

    func testLoginThroughTTYWithTwoFactor() async throws {
        let attempt = service.beginLogin(email: "me@example.com", password: "correct-horse")
        let outcome = try await attempt.start()
        XCTAssertEqual(outcome, .verificationRequired)
        let account = try await attempt.submitVerificationCode("123456")
        XCTAssertEqual(account, Account(name: "Test User", email: "me@example.com"))
    }

    func testLoginWrongPasswordIsClassified() async throws {
        let attempt = service.beginLogin(email: "me@example.com", password: "wrong")
        do {
            _ = try await attempt.start()
            XCTFail("expected failure")
        } catch let error as EngineError {
            XCTAssertEqual(error.kind, .invalidCredentials)
            XCTAssertFalse(error.rawMessage.contains("wrong"))
        }
    }

    func testLoginWrongCodeFails() async throws {
        let attempt = service.beginLogin(email: "me@example.com", password: "correct-horse")
        _ = try await attempt.start()
        do {
            _ = try await attempt.submitVerificationCode("000000")
            XCTFail("expected failure")
        } catch let error as EngineError {
            XCTAssertEqual(error.kind, .invalidResponse)
        }
    }

    func testLoginCancellationTerminatesProcess() async throws {
        let attempt = service.beginLogin(email: "me@example.com", password: "correct-horse")
        _ = try await attempt.start()
        attempt.cancel()
        do {
            _ = try await attempt.submitVerificationCode("123456")
        } catch let error as EngineError {
            XCTAssertTrue(error.kind == .cancelled || error.kind == .sessionExpired)
        }
    }

    func testSearchDecodes() async throws {
        let apps = try await service.search(term: "example", limit: 5, platform: .iPhone)
        XCTAssertEqual(apps.map(\.bundleID), ["com.example.app"])
    }

    func testDownloadReportsProgressAndOutputPath() async throws {
        let output = scriptURL.deletingLastPathComponent().appendingPathComponent("Example 1.0.ipa")
        let fractions = OSAllocatedUnfairLockBox<[Double]>([])
        let outcome = try await service.download(appID: 1, platform: .iPhone, output: output, externalVersionID: nil, acquireLicense: true) { progress in
            if let fraction = progress.fraction { fractions.withLock { $0.append(fraction) } }
        }
        XCTAssertEqual(outcome.fileURL, output)
        XCTAssertTrue(outcome.licenseAcquired)
        XCTAssertEqual(fractions.withLock { $0 }, [0.10, 0.55])
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }
}

import os
final class OSAllocatedUnfairLockBox<Value: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<Value>
    init(_ value: Value) { lock = OSAllocatedUnfairLock(initialState: value) }
    func withLock<R: Sendable>(_ body: @Sendable (inout Value) -> R) -> R { lock.withLock(body) }
}
