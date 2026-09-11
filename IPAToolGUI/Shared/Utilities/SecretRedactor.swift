import Foundation

/// Removes secrets from anything that might be logged or shown in diagnostics.
struct SecretRedactor: Sendable {
    static let mask = "••••••"

    /// Flags whose following argument is always a secret.
    static let secretFlags: Set<String> = ["--password", "-p", "--auth-code", "--keychain-passphrase"]

    /// JSON keys whose values are secrets in ipatool's verbose output.
    static let secretJSONKeys: [String] = ["password", "passwordToken", "authCode", "auth_code", "passphrase", "directoryServicesIdentifier"]

    private let knownSecrets: [String]

    init(knownSecrets: [String] = []) {
        self.knownSecrets = knownSecrets.filter { $0.count >= 2 }
    }

    func redact(_ text: String) -> String {
        var output = text
        for secret in knownSecrets {
            output = output.replacingOccurrences(of: secret, with: Self.mask)
        }
        for key in Self.secretJSONKeys {
            let pattern = "(\"\(key)\"\\s*:\\s*\")[^\"]*(\")"
            output = output.replacingOccurrences(of: pattern, with: "$1\(Self.mask)$2", options: .regularExpression)
        }
        for flag in Self.secretFlags {
            let pattern = "(\(NSRegularExpression.escapedPattern(for: flag))(?:=|\\s+))\\S+"
            output = output.replacingOccurrences(of: pattern, with: "$1\(Self.mask)", options: .regularExpression)
        }
        return output
    }

    func redact(arguments: [String]) -> [String] {
        var result: [String] = []
        var maskNext = false
        for argument in arguments {
            if maskNext {
                result.append(Self.mask)
                maskNext = false
                continue
            }
            if Self.secretFlags.contains(argument) {
                result.append(argument)
                maskNext = true
                continue
            }
            if let eq = argument.firstIndex(of: "="), Self.secretFlags.contains(String(argument[..<eq])) {
                result.append("\(argument[..<eq])=\(Self.mask)")
                continue
            }
            result.append(knownSecrets.contains(argument) ? Self.mask : argument)
        }
        return result
    }
}
