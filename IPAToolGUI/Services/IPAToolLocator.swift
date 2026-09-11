import Foundation

enum EngineDetection: Sendable, Equatable {
    case ready(url: URL, version: IPAToolVersion)
    case unsupported(url: URL, version: IPAToolVersion)
    case invalid(url: URL, reason: String)
    case notFound
}

/// Finds and validates the ipatool executable.
actor IPAToolLocator {
    private let runner: any ProcessRunning
    private let fileManager: FileManager

    static let wellKnownPaths: [String] = [
        "/opt/homebrew/bin/ipatool",
        "/usr/local/bin/ipatool",
        "~/.local/bin/ipatool",
        "~/bin/ipatool",
        "/opt/local/bin/ipatool",
    ]

    init(runner: any ProcessRunning, fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    /// Candidate executables in priority order: the user's choice, well-known paths, then PATH.
    func candidates(preferred: URL?) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        func add(_ path: String) {
            let expanded = (path as NSString).expandingTildeInPath
            guard !seen.contains(expanded), isExecutable(expanded) else { return }
            seen.insert(expanded)
            result.append(URL(fileURLWithPath: expanded))
        }
        if let preferred { add(preferred.path) }
        Self.wellKnownPaths.forEach(add)
        let pathVariable = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathVariable.split(separator: ":") where !directory.isEmpty {
            add("\(directory)/ipatool")
        }
        return result
    }

    private func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && fileManager.isExecutableFile(atPath: path)
    }

    /// Detects the first working binary. A preferred binary that fails validation is reported as invalid.
    func detect(preferred: URL?) async -> EngineDetection {
        if let preferred {
            let outcome = await validate(preferred)
            if case .notFound = outcome {} else { return outcome }
        }
        for candidate in candidates(preferred: nil) {
            let outcome = await validate(candidate)
            if case .ready = outcome { return outcome }
            if case .unsupported = outcome { return outcome }
        }
        return .notFound
    }

    func validate(_ url: URL) async -> EngineDetection {
        guard isExecutable(url.path) else {
            return fileManager.fileExists(atPath: url.path)
                ? .invalid(url: url, reason: "The file isn't executable.")
                : .notFound
        }
        let request = ProcessRequest(executable: url, arguments: IPAToolCommands.version().arguments,
                                     environment: IPAToolService.environment)
        do {
            let result = try await withTimeout(seconds: 10) { [runner] in
                try await runner.run(request)
            }
            let output = result.stdout + "\n" + result.stderr
            guard result.exitCode == 0, output.lowercased().contains("ipatool") || output.contains("version"),
                  let version = IPAToolVersion(parsing: output) else {
                return .invalid(url: url, reason: "This doesn't look like ipatool (\(output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))).")
            }
            return version.isSupported ? .ready(url: url, version: version) : .unsupported(url: url, version: version)
        } catch is TimeoutError {
            return .invalid(url: url, reason: "The binary didn't respond to --version.")
        } catch {
            return .invalid(url: url, reason: error.localizedDescription)
        }
    }
}

struct TimeoutError: Error, Sendable {}

/// Races an operation against a deadline; the loser is cancelled.
func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        guard let first = try await group.next() else { throw TimeoutError() }
        group.cancelAll()
        return first
    }
}
