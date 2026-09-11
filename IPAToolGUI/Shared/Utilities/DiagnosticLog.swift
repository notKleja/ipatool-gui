import Foundation
import Observation

struct DiagnosticEntry: Identifiable, Sendable, Hashable {
    let id = UUID()
    let timestamp: Date
    let command: String
    let exitCode: Int32?
    let duration: TimeInterval
    let note: String
}

/// Bounded, redacted, in-memory log of engine invocations for the Advanced settings pane.
@MainActor
@Observable
final class DiagnosticLog {
    private(set) var entries: [DiagnosticEntry] = []
    var isVerbose = false
    private let limit = 200

    func record(_ entry: DiagnosticEntry) {
        entries.append(entry)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    func clear() { entries.removeAll() }

    func report(engineStatus: String, account: String?) -> String {
        var lines: [String] = []
        lines.append("IPATool GUI diagnostic report")
        lines.append("Generated: \(Date.now.formatted(.iso8601))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Engine: \(engineStatus)")
        lines.append("Account: \(account ?? "signed out")")
        lines.append("")
        for entry in entries.suffix(50) {
            let code = entry.exitCode.map(String.init) ?? "—"
            lines.append("[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.command) → exit \(code) (\(String(format: "%.2f", entry.duration))s)")
            if !entry.note.isEmpty { lines.append("    \(entry.note)") }
        }
        return lines.joined(separator: "\n")
    }
}
