import XCTest
@testable import IPAToolGUI

final class ProcessRunnerTests: XCTestCase {
    private let runner = ProcessRunner()

    func testCapturesStdoutAndStderrAndExitCode() async throws {
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/bin/sh"),
                                     arguments: ["-c", "printf out; printf err 1>&2; exit 3"])
        let result = try await runner.run(request)
        XCTAssertEqual(result.stdout, "out")
        XCTAssertEqual(result.stderr, "err")
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertFalse(result.succeeded)
    }

    func testLargeOutputDoesNotDeadlock() async throws {
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/bin/sh"),
                                     arguments: ["-c", "i=0; while [ $i -lt 4000 ]; do echo 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'; echo 'e' 1>&2; i=$((i+1)); done"])
        let result = try await withTimeout(seconds: 30) { [runner] in try await runner.run(request) }
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.split(separator: "\n").count, 4000)
        XCTAssertEqual(result.stderr.split(separator: "\n").count, 4000)
    }

    func testStreamsOutputEvents() async throws {
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo one; echo two"])
        let collected = LineAccumulator()
        let result = try await runner.run(request) { event in
            if case .stdout(let text) = event { _ = collected.append(text) }
        }
        XCTAssertEqual(result.stdout, "one\ntwo\n")
    }

    func testCancellationTerminatesChild() async throws {
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 30"])
        let task = Task { [runner] in try await runner.run(request) }
        try await Task.sleep(for: .milliseconds(300))
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testPipeStdinIsDelivered() async throws {
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], standardInput: .pipe)
        let process = try runner.launch(request)
        var secret = Array("hunter2".utf8)
        try process.writeLine(secret: &secret)
        XCTAssertTrue(secret.allSatisfy { $0 == 0 }, "secret buffer must be zeroed")
        process.closeStandardInput()
        let result = await process.result()
        XCTAssertEqual(result.stdout, "hunter2\n")
    }

    func testPseudoTerminalStdinIsATTYWithoutEcho() async throws {
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/bin/sh"),
                                     arguments: ["-c", "if [ -t 0 ]; then echo tty; else echo notty; fi; read line; echo got:$line"],
                                     standardInput: .pseudoTerminal)
        let process = try runner.launch(request)
        var secret = Array("s3cret".utf8)
        try process.writeLine(secret: &secret)
        let result = await process.result()
        XCTAssertTrue(result.stdout.contains("tty\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("got:s3cret"), result.stdout)
    }

    func testMissingExecutableThrowsLaunchError() async {
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/nonexistent/ipatool"), arguments: ["--version"])
        do {
            _ = try await runner.run(request)
            XCTFail("expected launch failure")
        } catch {
            XCTAssertTrue(error is ProcessLaunchError)
        }
    }

    func testRedactedDescriptionHidesSecretsInArguments() {
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/usr/local/bin/ipatool"),
                                     arguments: ["auth", "login", "--email", "a@b.c", "--password", "pw", "--auth-code", "123456"],
                                     secrets: ["pw"])
        XCTAssertEqual(request.redactedDescription, "ipatool auth login --email a@b.c --password •••••• --auth-code ••••••")
    }

    func testUTF8DecoderHandlesSplitSequences() {
        var decoder = UTF8ChunkDecoder()
        let euro = Array("€".utf8)
        XCTAssertEqual(decoder.decode(Data([euro[0]])), "")
        XCTAssertEqual(decoder.decode(Data([euro[1]])), "")
        XCTAssertEqual(decoder.decode(Data([euro[2], 0x41])), "€A")
        XCTAssertEqual(decoder.flush(), "")
    }
}
