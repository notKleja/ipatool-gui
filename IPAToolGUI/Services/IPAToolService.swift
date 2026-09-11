import Foundation
import os

enum LoginOutcome: Sendable, Equatable {
    case signedIn(Account)
    case verificationRequired
}

/// One in-flight `ipatool auth login` conversation.
protocol LoginAttempt: AnyObject, Sendable {
    func start() async throws -> LoginOutcome
    func submitVerificationCode(_ code: String) async throws -> Account
    func cancel()
}

struct LicenseResult: Sendable, Equatable {
    let alreadyOwned: Bool
}

struct DownloadOutcome: Sendable, Equatable {
    let fileURL: URL
    let licenseAcquired: Bool
}

struct DownloadProgress: Sendable, Equatable {
    /// 0…1, or nil while progress is unknown.
    let fraction: Double?
}

protocol IPAToolServing: Sendable {
    func version() async throws -> IPAToolVersion
    func accountInfo() async throws -> Account?
    func beginLogin(email: String, password: String) -> any LoginAttempt
    func revokeAuthentication() async throws
    func search(term: String, limit: Int, platform: AppPlatform) async throws -> [AppStoreApp]
    func purchasedApps(page: Int, pageSize: Int) async throws -> PurchasedPage
    func acquireLicense(bundleID: String, platform: AppPlatform) async throws -> LicenseResult
    func versions(appID: Int64) async throws -> [ExternalVersionID]
    func versionMetadata(appID: Int64, externalVersionID: ExternalVersionID) async throws -> AppVersion
    func download(appID: Int64, platform: AppPlatform, output: URL, externalVersionID: ExternalVersionID?,
                  acquireLicense: Bool, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> DownloadOutcome
}

struct IPAToolConfiguration: Sendable, Equatable {
    var executable: URL?
    var verbose: Bool

    init(executable: URL? = nil, verbose: Bool = false) {
        self.executable = executable
        self.verbose = verbose
    }
}

/// Real implementation that shells out to the configured ipatool binary through `ProcessRunning`.
final class IPAToolService: IPAToolServing, Sendable {
    private let runner: any ProcessRunning
    private let configuration: OSAllocatedUnfairLock<IPAToolConfiguration>

    init(runner: any ProcessRunning, configuration: IPAToolConfiguration = .init()) {
        self.runner = runner
        self.configuration = OSAllocatedUnfairLock(initialState: configuration)
    }

    func update(configuration: IPAToolConfiguration) {
        self.configuration.withLock { $0 = configuration }
    }

    var currentConfiguration: IPAToolConfiguration { configuration.withLock { $0 } }

    private var verbose: Bool { currentConfiguration.verbose }

    private func makeRequest(_ command: IPAToolCommand, secrets: [String] = []) throws -> ProcessRequest {
        guard let executable = currentConfiguration.executable else { throw EngineError.notInstalled }
        return ProcessRequest(executable: executable, arguments: command.arguments,
                              environment: Self.environment, standardInput: command.standardInput, secrets: secrets)
    }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        return env
    }

    private func execute(_ command: IPAToolCommand,
                         onEvent: (@Sendable (ProcessOutputEvent) -> Void)? = nil) async throws -> ProcessResult {
        let request = try makeRequest(command)
        let result: ProcessResult
        do {
            result = try await runner.run(request, onEvent: onEvent)
        } catch let launchError as ProcessLaunchError {
            throw EngineError(kind: .engineNotInstalled, rawMessage: launchError.errorDescription ?? "")
        } catch is CancellationError {
            throw EngineError.cancelled
        }
        guard result.succeeded else { throw ErrorClassifier.error(fromResult: result) }
        return result
    }

    // MARK: - IPAToolServing

    func version() async throws -> IPAToolVersion {
        let result = try await execute(IPAToolCommands.version())
        guard let version = IPAToolVersion(parsing: result.stdout + result.stderr) else {
            throw EngineError(kind: .unsupportedVersion, rawMessage: "Unrecognized version output: \(result.stdout)")
        }
        return version
    }

    func accountInfo() async throws -> Account? {
        do {
            let result = try await execute(IPAToolCommands.authInfo(verbose: verbose))
            let account = try IPAToolOutput.decodeResult(Account.self, from: result.stdout)
            return account.email.isEmpty ? nil : account
        } catch let error as EngineError where error.kind == .notAuthenticated {
            return nil
        }
    }

    func beginLogin(email: String, password: String) -> any LoginAttempt {
        IPAToolLoginAttempt(runner: runner, configuration: currentConfiguration, email: email, password: password)
    }

    func revokeAuthentication() async throws {
        do {
            _ = try await execute(IPAToolCommands.authRevoke(verbose: verbose))
        } catch let error as EngineError where error.kind == .notAuthenticated {
            return
        }
    }

    func search(term: String, limit: Int, platform: AppPlatform) async throws -> [AppStoreApp] {
        let result = try await execute(IPAToolCommands.search(term: term, limit: limit, platform: platform, verbose: verbose))
        return try IPAToolOutput.decodeResult(SearchResponse.self, from: result.stdout).apps
    }

    func purchasedApps(page: Int, pageSize: Int) async throws -> PurchasedPage {
        let result = try await execute(IPAToolCommands.listPurchases(page: page, maxResults: pageSize, verbose: verbose))
        return try IPAToolOutput.decodeResult(PurchasedPage.self, from: result.stdout)
    }

    func acquireLicense(bundleID: String, platform: AppPlatform) async throws -> LicenseResult {
        let result = try await execute(IPAToolCommands.purchase(bundleID: bundleID, platform: platform, verbose: verbose))
        let object = IPAToolOutput.jsonObjects(in: result.stdout).last ?? [:]
        return LicenseResult(alreadyOwned: object["alreadyOwned"] as? Bool ?? false)
    }

    func versions(appID: Int64) async throws -> [ExternalVersionID] {
        let result = try await execute(IPAToolCommands.listVersions(appID: appID, verbose: verbose))
        return try IPAToolOutput.decodeResult(ListVersionsResponse.self, from: result.stdout).externalVersionIdentifiers
    }

    func versionMetadata(appID: Int64, externalVersionID: ExternalVersionID) async throws -> AppVersion {
        let command = IPAToolCommands.versionMetadata(appID: appID, externalVersionID: externalVersionID, verbose: verbose)
        let result = try await execute(command)
        return try IPAToolOutput.decodeResult(AppVersion.self, from: result.stdout)
    }

    func download(appID: Int64, platform: AppPlatform, output: URL, externalVersionID: ExternalVersionID?,
                  acquireLicense: Bool, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> DownloadOutcome {
        let command = IPAToolCommands.download(appID: appID, platform: platform, output: output,
                                               externalVersionID: externalVersionID, acquireLicense: acquireLicense, verbose: verbose)
        let splitter = LineAccumulator()
        let result = try await execute(command) { event in
            guard case .stdout(let chunk) = event else { return }
            for line in splitter.append(chunk) where !line.hasPrefix("{") {
                if let fraction = IPAToolOutput.progressFraction(in: line) {
                    progress(DownloadProgress(fraction: fraction))
                }
            }
        }
        let object = IPAToolOutput.jsonObjects(in: result.stdout).last(where: { $0["success"] != nil }) ?? [:]
        guard let path = object["output"] as? String, !path.isEmpty else {
            throw EngineError(kind: .invalidResponse, rawMessage: "ipatool did not report an output path",
                              diagnostics: result.diagnosticSummary)
        }
        return DownloadOutcome(fileURL: URL(fileURLWithPath: path), licenseAcquired: object["purchased"] as? Bool ?? false)
    }
}

/// Splits streamed text into lines on `\n` and `\r`, buffering partial lines between chunks.
final class LineAccumulator: Sendable {
    private let buffer = OSAllocatedUnfairLock(initialState: "")

    func append(_ chunk: String) -> [String] {
        buffer.withLock { buffer in
            buffer += chunk
            var lines: [String] = []
            while let range = buffer.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n")) {
                let line = String(buffer[buffer.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                if !line.isEmpty { lines.append(line) }
            }
            return lines
        }
    }

    func flush() -> String? {
        buffer.withLock { buffer in
            defer { buffer = "" }
            let line = buffer.trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : line
        }
    }
}

/// Drives `ipatool auth login` over a pseudo-terminal.
///
/// Security notes:
/// - The password is written to the TTY once ipatool asks for it, never passed on the command line.
/// - The byte buffer is zeroed right after being written. The original `String` is released with the attempt.
/// - Verification codes are written once and never stored.
actor IPAToolLoginAttempt: LoginAttempt {
    private let runner: any ProcessRunning
    private let configuration: IPAToolConfiguration
    private let email: String
    private var passwordBytes: [UInt8]
    private var process: RunningProcess?
    private var pumpTask: Task<Void, Never>?
    private let lines = LineAccumulator()
    private var finished = false
    private var waiter: CheckedContinuation<LoginOutcome, any Error>?
    private var pendingResult: Result<LoginOutcome, any Error>?

    init(runner: any ProcessRunning, configuration: IPAToolConfiguration, email: String, password: String) {
        self.runner = runner
        self.configuration = configuration
        self.email = email
        self.passwordBytes = Array(password.utf8)
    }

    func start() async throws -> LoginOutcome {
        guard let executable = configuration.executable else { throw EngineError.notInstalled }
        let command = IPAToolCommands.authLogin(email: email, verbose: configuration.verbose)
        let request = ProcessRequest(executable: executable, arguments: command.arguments,
                                     environment: IPAToolService.environment, standardInput: command.standardInput)
        let process: RunningProcess
        do {
            process = try runner.launch(request)
        } catch {
            zeroPassword()
            throw EngineError(kind: .engineNotInstalled, rawMessage: error.localizedDescription)
        }
        self.process = process
        pumpTask = Task { [weak self] in
            for await event in process.events {
                await self?.handle(event: event, process: process)
            }
            await self?.handleExit(process: process)
        }
        return try await nextOutcome()
    }

    func submitVerificationCode(_ code: String) async throws -> Account {
        guard let process, !finished else { throw EngineError(kind: .sessionExpired, rawMessage: "Login attempt is no longer active") }
        var bytes = Array(code.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        try process.writeLine(secret: &bytes)
        switch try await nextOutcome() {
        case .signedIn(let account): return account
        case .verificationRequired:
            throw EngineError(kind: .twoFactorRequired, rawMessage: "ipatool asked for a verification code again")
        }
    }

    nonisolated func cancel() {
        Task { await self.terminate() }
    }

    private func terminate() {
        process?.terminate()
        zeroPassword()
        finished = true
        deliver(.failure(EngineError.cancelled))
    }

    private func zeroPassword() {
        for index in passwordBytes.indices { passwordBytes[index] = 0 }
        passwordBytes.removeAll()
    }

    private func nextOutcome() async throws -> LoginOutcome {
        if let pending = pendingResult {
            pendingResult = nil
            return try pending.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
        }
    }

    private func deliver(_ result: Result<LoginOutcome, any Error>) {
        if let waiter {
            self.waiter = nil
            waiter.resume(with: result)
        } else if pendingResult == nil {
            pendingResult = result
        }
    }

    private func handle(event: ProcessOutputEvent, process: RunningProcess) {
        guard case .stdout(let chunk) = event, !finished else { return }
        for line in lines.append(chunk) {
            handle(line: line, process: process)
            if finished { return }
        }
    }

    private func handleExit(process: RunningProcess) async {
        if let tail = lines.flush() { handle(line: tail, process: process) }
        let result = await process.result()
        guard !finished else { return }
        finished = true
        zeroPassword()
        if result.succeeded, let account = try? IPAToolOutput.decodeResult(Account.self, from: result.stdout), !account.email.isEmpty {
            deliver(.success(.signedIn(account)))
        } else {
            deliver(.failure(ErrorClassifier.error(fromResult: result)))
        }
    }

    private func handle(line: String, process: RunningProcess) {
        guard line.hasPrefix("{"), let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let message = (object["message"] as? String ?? "").lowercased()
        let level = object["level"] as? String ?? "info"

        if level == "error" || object["error"] != nil {
            let raw = (object["error"] as? String) ?? (object["message"] as? String) ?? "login failed"
            finished = true
            zeroPassword()
            deliver(.failure(EngineError(kind: ErrorClassifier.classify(message: raw), rawMessage: SecretRedactor().redact(raw))))
            return
        }
        if message.contains("enter password") {
            do {
                try process.writeLine(secret: &passwordBytes)
            } catch {
                finished = true
                zeroPassword()
                process.terminate()
                deliver(.failure(EngineError(kind: .unknown, rawMessage: "Couldn't send the password to ipatool: \(error.localizedDescription)")))
            }
            return
        }
        if message.contains("2fa code") || message.contains("verification code") || message.contains("auth code") {
            zeroPassword()
            deliver(.success(.verificationRequired))
            return
        }
        if object["success"] as? Bool == true, let emailValue = object["email"] as? String, !emailValue.isEmpty {
            finished = true
            zeroPassword()
            let name = (object["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            deliver(.success(.signedIn(Account(name: name, email: emailValue))))
        }
    }
}
