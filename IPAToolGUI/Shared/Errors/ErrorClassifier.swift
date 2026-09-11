import Foundation

/// Turns ipatool's error strings (and exit status) into `EngineErrorKind`s.
/// Patterns come from `pkg/appstore/*.go` and `cmd/*.go` upstream; keep them lowercase.
enum ErrorClassifier {
    private static let rules: [(EngineErrorKind, [String])] = [
        (.twoFactorRequired, ["auth code is required", "2fa code is required"]),
        (.notAuthenticated, [
            "could not be found in the keychain",
            "failed to get account",
            "item not found",
            "keyring: not found",
            "not authenticated",
        ]),
        (.keychainLocked, ["keychain passphrase", "failed to read password", "unlock"]),
        (.invalidCredentials, [
            "entered incorrectly",
            "password was incorrect",
            "badlogin",
            "invalid credentials",
            "-5000",
        ]),
        (.accountDisabled, ["account is disabled", "your account is disabled"]),
        (.tooManyAttempts, ["too many attempts"]),
        (.sessionExpired, ["password token is expired", "sign in required", "password has changed"]),
        (.licenseRequired, ["license is required", "license not found"]),
        (.paidAppNotSupported, ["purchasing paid apps is not supported"]),
        (.subscriptionRequired, ["subscription required"]),
        (.temporarilyUnavailable, ["temporarily unavailable"]),
        (.unavailableInStorefront, [
            "not available in your country",
            "not available in the storefront",
            "storefront",
            "is not available",
        ]),
        (.appNotFound, ["app not found", "returned no app"]),
        (.versionUnavailable, [
            "could not find info.plist",
            "does not contain a display version",
            "does not contain a release date",
            "failed to get version metadata",
            "external version",
            "version lookup",
        ]),
        (.diskFull, ["no space left on device"]),
        (.outputNotWritable, [
            "permission denied",
            "read-only file system",
            "is a directory",
            "failed to open file",
            "failed to determine whether path is a directory",
            "failed to resolve destination path",
            "not a directory",
        ]),
        (.network, [
            "no such host",
            "dial tcp",
            "connection refused",
            "connection reset",
            "i/o timeout",
            "timeout",
            "network is unreachable",
            "tls",
            "eof",
            "request failed",
            "failed to send http request",
            "context deadline exceeded",
        ]),
        (.invalidResponse, ["invalid response", "something went wrong", "failed to unmarshal", "failed to decode"]),
    ]

    static func classify(message: String) -> EngineErrorKind {
        let lower = message.lowercased()
        if lower.isEmpty { return .unknown }
        for (kind, needles) in rules where needles.contains(where: { lower.contains($0) }) {
            return kind
        }
        return .unknown
    }

    /// Builds an `EngineError` from process output. Prefers the structured `error` field of the last JSON line.
    static func error(fromResult result: ProcessResult, redactor: SecretRedactor = .init()) -> EngineError {
        if result.wasTerminated { return .cancelled }
        let message = IPAToolOutput.errorMessage(in: result.stdout)
            ?? IPAToolOutput.errorMessage(in: result.stderr)
            ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init)
            ?? "ipatool exited with status \(result.exitCode)"
        let kind = classify(message: message)
        let diagnostics = redactor.redact(result.diagnosticSummary)
        return EngineError(kind: kind, rawMessage: redactor.redact(message), diagnostics: diagnostics)
    }
}
