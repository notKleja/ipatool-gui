import Foundation

/// Parsed output of `ipatool --version`.
struct IPAToolVersion: Sendable, Hashable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let raw: String

    /// Oldest release exposing the whole command surface this app depends on.
    static let minimumSupported = IPAToolVersion(major: 2, minor: 2, patch: 0, raw: "2.2.0")
    /// Release this app was validated against.
    static let recommended = IPAToolVersion(major: 2, minor: 5, patch: 0, raw: "2.5.0")

    init(major: Int, minor: Int, patch: Int, raw: String) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.raw = raw
    }

    /// Accepts "ipatool version 2.5.0", "2.5.0", "v2.5.0-rc.1", "ipatool 2.5.0 (abcdef)".
    init?(parsing output: String) {
        let pattern = #"(\d+)\.(\d+)(?:\.(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let majorRange = Range(match.range(at: 1), in: output),
              let minorRange = Range(match.range(at: 2), in: output),
              let major = Int(output[majorRange]),
              let minor = Int(output[minorRange]) else { return nil }
        let patch: Int
        if let patchRange = Range(match.range(at: 3), in: output), let p = Int(output[patchRange]) {
            patch = p
        } else {
            patch = 0
        }
        self.init(major: major, minor: minor, patch: patch,
                  raw: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var description: String { "\(major).\(minor).\(patch)" }

    var isSupported: Bool { self >= .minimumSupported }
    var isRecommendedOrNewer: Bool { self >= .recommended }
}

extension IPAToolVersion: Comparable {
    static func < (lhs: IPAToolVersion, rhs: IPAToolVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    static func == (lhs: IPAToolVersion, rhs: IPAToolVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) == (rhs.major, rhs.minor, rhs.patch)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(major); hasher.combine(minor); hasher.combine(patch)
    }
}
