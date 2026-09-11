import Foundation
import Observation

/// Installs ipatool through Homebrew, only after the user explicitly confirms.
@MainActor
@Observable
final class EngineInstaller {
    enum State: Equatable {
        case idle
        case running
        case failed(String)
        case succeeded
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""

    @ObservationIgnored private let runner: any ProcessRunning
    @ObservationIgnored private var task: Task<Void, Never>?

    static let homebrewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    static let releasesURL = URL(string: "https://github.com/majd/ipatool/releases/latest")!

    init(runner: any ProcessRunning) {
        self.runner = runner
    }

    var homebrewURL: URL? {
        Self.homebrewCandidates.map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var isRunning: Bool { state == .running }

    /// Runs `brew install ipatool`; `completion` is invoked on success so the caller can re-detect.
    func installWithHomebrew(completion: @escaping @MainActor () async -> Void) {
        guard let brew = homebrewURL, !isRunning else { return }
        state = .running
        transcript = ""
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["NONINTERACTIVE"] = "1"
        environment["PATH"] = "\(brew.deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin"
        let request = ProcessRequest(executable: brew, arguments: ["install", "ipatool"], environment: environment)
        task = Task { [runner] in
            do {
                let result = try await runner.run(request) { [weak self] event in
                    let text: String
                    switch event {
                    case .stdout(let chunk), .stderr(let chunk): text = chunk
                    }
                    Task { @MainActor in self?.append(text) }
                }
                if result.succeeded {
                    state = .succeeded
                    await completion()
                } else {
                    state = .failed("Homebrew exited with status \(result.exitCode).")
                }
            } catch {
                state = EngineError.wrap(error).isCancellation ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func append(_ text: String) {
        transcript += text
        if transcript.count > 20_000 { transcript = String(transcript.suffix(20_000)) }
    }
}
