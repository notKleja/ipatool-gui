import Foundation

enum FilenameSanitizer {
    private static let forbidden: Set<Character> = ["/", ":", "\0", "\\", "?", "*", "\"", "<", ">", "|"]
    static let maximumLength = 200

    /// Produces a filesystem-safe base name (no extension) from user-visible text.
    static func sanitize(_ raw: String, fallback: String = "App") -> String {
        var result = raw
            .replacingOccurrences(of: "\u{0}", with: "")
            .map { forbidden.contains($0) || $0.isNewline || ($0.unicodeScalars.first.map { $0.value < 0x20 } ?? false) ? "-" : $0 }
            .reduce(into: "") { $0.append($1) }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix(".") { result.removeFirst() }
        result = result.trimmingCharacters(in: .whitespaces)
        if result.count > maximumLength {
            result = String(result.prefix(maximumLength)).trimmingCharacters(in: .whitespaces)
        }
        return result.isEmpty ? fallback : result
    }

    /// "App Name 7.4.1.ipa" style filename for a package.
    static func packageFilename(appName: String, version: String?, platform: AppPlatform, bundleID: String) -> String {
        let base = sanitize(appName, fallback: sanitize(bundleID))
        let trimmedVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stem = trimmedVersion.isEmpty ? base : "\(base) \(sanitize(trimmedVersion, fallback: ""))".trimmingCharacters(in: .whitespaces)
        return "\(stem).\(platform.packageExtension)"
    }

    /// Returns a URL that doesn't exist yet by appending " (2)", " (3)"… before the extension.
    static func uniqueURL(for url: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        var counter = 2
        while true {
            let candidate = directory.appendingPathComponent("\(stem) (\(counter))").appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}
