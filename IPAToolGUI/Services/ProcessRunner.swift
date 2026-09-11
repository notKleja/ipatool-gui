import Foundation
import os

enum StandardInputMode: Sendable {
    /// stdin is /dev/null.
    case none
    /// stdin is a pipe; write with `RunningProcess.write`.
    case pipe
    /// stdin is a pseudo-terminal with echo disabled (needed for `term.ReadPassword`).
    case pseudoTerminal
}

struct ProcessRequest: Sendable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]?
    var standardInput: StandardInputMode
    var currentDirectory: URL?
    /// Values that must never appear in logs or diagnostics.
    var secrets: [String]

    init(executable: URL, arguments: [String], environment: [String: String]? = nil,
         standardInput: StandardInputMode = .none, currentDirectory: URL? = nil, secrets: [String] = []) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.standardInput = standardInput
        self.currentDirectory = currentDirectory
        self.secrets = secrets
    }

    /// Redacted, human-readable command line for diagnostics.
    var redactedDescription: String {
        let redactor = SecretRedactor(knownSecrets: secrets)
        return ([executable.lastPathComponent] + redactor.redact(arguments: arguments)).joined(separator: " ")
    }
}

enum ProcessOutputEvent: Sendable {
    case stdout(String)
    case stderr(String)
}

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let wasTerminated: Bool
    let duration: TimeInterval
    let commandDescription: String

    var succeeded: Bool { exitCode == 0 && !wasTerminated }

    var diagnosticSummary: String {
        var lines = ["$ \(commandDescription)", "exit: \(exitCode)\(wasTerminated ? " (terminated)" : "")"]
        let trimmedErr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedErr.isEmpty { lines.append("stderr:\n\(trimmedErr.suffix(2000))") }
        let trimmedOut = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOut.isEmpty {
            let lastLines = IPAToolOutput.lines(in: trimmedOut).suffix(5).joined(separator: "\n")
            lines.append("stdout (tail):\n\(lastLines.suffix(2000))")
        }
        return lines.joined(separator: "\n")
    }
}

protocol ProcessRunning: Sendable {
    func launch(_ request: ProcessRequest) throws -> RunningProcess
}

extension ProcessRunning {
    /// Runs to completion, forwarding output chunks as they arrive. Cancelling the task terminates the child.
    func run(_ request: ProcessRequest,
             onEvent: (@Sendable (ProcessOutputEvent) -> Void)? = nil) async throws -> ProcessResult {
        try Task.checkCancellation()
        let process = try launch(request)
        return try await withTaskCancellationHandler {
            for await event in process.events {
                onEvent?(event)
            }
            let result = await process.result()
            if Task.isCancelled { throw CancellationError() }
            return result
        } onCancel: {
            process.terminate()
        }
    }
}

struct ProcessLaunchError: Error, LocalizedError, Sendable {
    let path: String
    let underlying: String
    var errorDescription: String? { "Couldn't launch \(path): \(underlying)" }
}

/// A live child process. Thread-safe; all bookkeeping happens under one lock.
final class RunningProcess: Sendable {
    let events: AsyncStream<ProcessOutputEvent>
    let request: ProcessRequest

    private struct State: Sendable {
        var stdoutDone = false
        var stderrDone = false
        var exited = false
        var exitCode: Int32 = 0
        var terminatedByUs = false
        var finished = false
        var stdout = ""
        var stderr = ""
        var stdoutDecoder = UTF8ChunkDecoder()
        var stderrDecoder = UTF8ChunkDecoder()
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let process: Process
    private let continuation: AsyncStream<ProcessOutputEvent>.Continuation
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdinPipe: Pipe?
    private let pty: PseudoTerminal?
    private let ptyMasterHandle: FileHandle?
    private let startedAt = Date()
    private let onFinish: (@Sendable (ProcessResult) -> Void)?

    init(request: ProcessRequest, onFinish: (@Sendable (ProcessResult) -> Void)? = nil) throws {
        self.request = request
        self.onFinish = onFinish

        var continuation: AsyncStream<ProcessOutputEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation

        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.qualityOfService = .userInitiated
        if let environment = request.environment { process.environment = environment }
        if let directory = request.currentDirectory { process.currentDirectoryURL = directory }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        switch request.standardInput {
        case .none:
            stdinPipe = nil
            pty = nil
            ptyMasterHandle = nil
            process.standardInput = FileHandle.nullDevice
        case .pipe:
            let pipe = Pipe()
            stdinPipe = pipe
            pty = nil
            ptyMasterHandle = nil
            process.standardInput = pipe
        case .pseudoTerminal:
            let terminal = try PseudoTerminal.open()
            stdinPipe = nil
            pty = terminal
            ptyMasterHandle = FileHandle(fileDescriptor: terminal.masterDescriptor, closeOnDealloc: false)
            process.standardInput = FileHandle(fileDescriptor: terminal.slaveDescriptor, closeOnDealloc: false)
        }
        self.process = process

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isStdout: true)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isStdout: false)
        }
        // Drain the master side so echoes or prompts written to the TTY can never fill the buffer.
        ptyMasterHandle?.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
        }
        process.terminationHandler = { [weak self] finished in
            self?.handleExit(status: finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            ptyMasterHandle?.readabilityHandler = nil
            pty?.closeSlave()
            pty?.closeMaster()
            continuation.finish()
            throw ProcessLaunchError(path: request.executable.path, underlying: error.localizedDescription)
        }
        // The child owns its own copy of the slave descriptor now.
        pty?.closeSlave()
    }

    var processIdentifier: Int32 { process.processIdentifier }

    /// Writes bytes to the child's stdin (pipe or TTY). The caller should zero secret buffers afterwards.
    func write(_ bytes: [UInt8]) throws {
        let data = Data(bytes)
        if let pty {
            let handle = FileHandle(fileDescriptor: pty.masterDescriptor, closeOnDealloc: false)
            try handle.write(contentsOf: data)
        } else if let stdinPipe {
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        } else {
            throw ProcessLaunchError(path: request.executable.path, underlying: "stdin is not writable")
        }
    }

    /// Writes a secret followed by a newline, then zeroes the caller's buffer.
    func writeLine(secret: inout [UInt8]) throws {
        var line = secret
        line.append(UInt8(ascii: "\n"))
        defer {
            for index in line.indices { line[index] = 0 }
            for index in secret.indices { secret[index] = 0 }
        }
        try write(line)
    }

    func closeStandardInput() {
        try? stdinPipe?.fileHandleForWriting.close()
    }

    /// Sends SIGTERM. Safe to call repeatedly.
    func terminate() {
        let shouldSignal = state.withLock { state -> Bool in
            guard !state.exited else { return false }
            state.terminatedByUs = true
            return true
        }
        if shouldSignal, process.isRunning {
            process.terminate()
        }
    }

    /// Sends SIGKILL for children that ignore SIGTERM.
    func kill() {
        let shouldSignal = state.withLock { state -> Bool in
            guard !state.exited else { return false }
            state.terminatedByUs = true
            return true
        }
        if shouldSignal, process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }

    /// Suspends until the process has exited and both output pipes reached EOF.
    func result() async -> ProcessResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyFinished = state.withLock { state -> Bool in
                if state.finished { return true }
                state.waiters.append(continuation)
                return false
            }
            if alreadyFinished { continuation.resume() }
        }
        return makeResult()
    }

    private func makeResult() -> ProcessResult {
        state.withLock { state in
            ProcessResult(stdout: state.stdout, stderr: state.stderr, exitCode: state.exitCode,
                          wasTerminated: state.terminatedByUs, duration: Date().timeIntervalSince(startedAt),
                          commandDescription: request.redactedDescription)
        }
    }

    private func consume(_ data: Data, isStdout: Bool) {
        if data.isEmpty {
            (isStdout ? stdoutPipe : stderrPipe).fileHandleForReading.readabilityHandler = nil
            let tail: String = state.withLock { state in
                if isStdout {
                    state.stdoutDone = true
                    let text = state.stdoutDecoder.flush()
                    state.stdout += text
                    return text
                } else {
                    state.stderrDone = true
                    let text = state.stderrDecoder.flush()
                    state.stderr += text
                    return text
                }
            }
            if !tail.isEmpty { continuation.yield(isStdout ? .stdout(tail) : .stderr(tail)) }
            finishIfNeeded()
            return
        }
        let text: String = state.withLock { state in
            if isStdout {
                let text = state.stdoutDecoder.decode(data)
                state.stdout += text
                return text
            } else {
                let text = state.stderrDecoder.decode(data)
                state.stderr += text
                return text
            }
        }
        if !text.isEmpty { continuation.yield(isStdout ? .stdout(text) : .stderr(text)) }
    }

    private func handleExit(status: Int32) {
        state.withLock { state in
            state.exited = true
            state.exitCode = status
        }
        finishIfNeeded()
    }

    private func finishIfNeeded() {
        let waiters: [CheckedContinuation<Void, Never>]? = state.withLock { state in
            guard state.exited, state.stdoutDone, state.stderrDone, !state.finished else { return nil }
            state.finished = true
            let waiters = state.waiters
            state.waiters.removeAll()
            return waiters
        }
        guard let waiters else { return }
        ptyMasterHandle?.readabilityHandler = nil
        pty?.closeMaster()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
        try? stdinPipe?.fileHandleForWriting.close()
        continuation.finish()
        onFinish?(makeResult())
        for waiter in waiters { waiter.resume() }
    }
}

/// Default `ProcessRunning` implementation. Records a redacted diagnostic entry for every run.
final class ProcessRunner: ProcessRunning {
    private let diagnosticsSink: (@Sendable (DiagnosticEntry) -> Void)?

    init(diagnosticsSink: (@Sendable (DiagnosticEntry) -> Void)? = nil) {
        self.diagnosticsSink = diagnosticsSink
    }

    func launch(_ request: ProcessRequest) throws -> RunningProcess {
        let sink = diagnosticsSink
        let redactor = SecretRedactor(knownSecrets: request.secrets)
        return try RunningProcess(request: request) { result in
            guard let sink else { return }
            let note: String
            if result.succeeded {
                note = ""
            } else {
                note = redactor.redact(IPAToolOutput.errorMessage(in: result.stdout)
                    ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300).description)
            }
            sink(DiagnosticEntry(timestamp: .now, command: result.commandDescription,
                                 exitCode: result.exitCode, duration: result.duration, note: note))
        }
    }
}
