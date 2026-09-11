import Foundation

/// Domain-level classification of anything that can go wrong while talking to ipatool.
enum EngineErrorKind: String, Codable, Sendable, Hashable, CaseIterable {
    case engineNotInstalled
    case unsupportedVersion
    case notAuthenticated
    case twoFactorRequired
    case invalidCredentials
    case accountDisabled
    case tooManyAttempts
    case sessionExpired
    case licenseRequired
    case paidAppNotSupported
    case appNotFound
    case unavailableInStorefront
    case temporarilyUnavailable
    case subscriptionRequired
    case network
    case invalidResponse
    case versionUnavailable
    case outputNotWritable
    case diskFull
    case cancelled
    case keychainLocked
    case unknown

    var title: String {
        switch self {
        case .engineNotInstalled: "ipatool Is Not Installed"
        case .unsupportedVersion: "Unsupported ipatool Version"
        case .notAuthenticated: "Sign In Required"
        case .twoFactorRequired: "Verification Required"
        case .invalidCredentials: "Incorrect Apple Account or Password"
        case .accountDisabled: "Account Disabled"
        case .tooManyAttempts: "Too Many Attempts"
        case .sessionExpired: "Session Expired"
        case .licenseRequired: "App Not Acquired"
        case .paidAppNotSupported: "Paid App"
        case .appNotFound: "App Not Found"
        case .unavailableInStorefront: "Not Available in Your Storefront"
        case .temporarilyUnavailable: "Temporarily Unavailable"
        case .subscriptionRequired: "Subscription Required"
        case .network: "Network Problem"
        case .invalidResponse: "Unexpected Response"
        case .versionUnavailable: "Version Unavailable"
        case .outputNotWritable: "Can't Write to Download Location"
        case .diskFull: "Not Enough Disk Space"
        case .cancelled: "Cancelled"
        case .keychainLocked: "Keychain Locked"
        case .unknown: "Something Went Wrong"
        }
    }

    var message: String {
        switch self {
        case .engineNotInstalled:
            "IPATool needs the ipatool command-line engine. Install it and choose it in Settings."
        case .unsupportedVersion:
            "This version of ipatool is too old. Update to \(IPAToolVersion.recommended) or newer."
        case .notAuthenticated:
            "Sign in with your Apple Account to use the App Store."
        case .twoFactorRequired:
            "Enter the verification code sent to your trusted Apple device."
        case .invalidCredentials:
            "Check your Apple Account email and password and try again."
        case .accountDisabled:
            "This Apple Account is disabled. Resolve the issue at appleid.apple.com."
        case .tooManyAttempts:
            "Apple rejected the sign-in attempt. Wait a moment before trying again."
        case .sessionExpired:
            "Your App Store session is no longer valid. Sign in again."
        case .licenseRequired:
            "This app hasn't been acquired by this Apple Account."
        case .paidAppNotSupported:
            "ipatool can only acquire free apps. Buy this app in the App Store first, then download it here."
        case .appNotFound:
            "The App Store didn't return an app for this identifier."
        case .unavailableInStorefront:
            "This app isn't available in the App Store storefront tied to your Apple Account."
        case .temporarilyUnavailable:
            "The App Store reported this item as temporarily unavailable."
        case .subscriptionRequired:
            "This item requires a subscription and can't be acquired here."
        case .network:
            "Couldn't reach the App Store. Check your connection and try again."
        case .invalidResponse:
            "The App Store returned something ipatool couldn't understand."
        case .versionUnavailable:
            "This version can't be resolved or downloaded any more."
        case .outputNotWritable:
            "Choose a different download location in Settings."
        case .diskFull:
            "Free up space or choose a different download location."
        case .cancelled:
            "The operation was cancelled."
        case .keychainLocked:
            "ipatool couldn't unlock its keychain item. Approve the keychain prompt or sign in again."
        case .unknown:
            "ipatool reported an error. Open Show Details for the technical message."
        }
    }
}

/// Error surfaced to the UI. `rawMessage` and `diagnostics` are already redacted.
struct EngineError: Error, Sendable, Hashable, LocalizedError {
    let kind: EngineErrorKind
    let rawMessage: String
    let diagnostics: String?

    init(kind: EngineErrorKind, rawMessage: String = "", diagnostics: String? = nil) {
        self.kind = kind
        self.rawMessage = rawMessage
        self.diagnostics = diagnostics
    }

    static let cancelled = EngineError(kind: .cancelled)
    static let notInstalled = EngineError(kind: .engineNotInstalled)

    var errorDescription: String? { kind.title }
    var failureReason: String? { kind.message }
    var recoverySuggestion: String? { nil }

    var detailText: String {
        var parts: [String] = []
        if !rawMessage.isEmpty { parts.append(rawMessage) }
        if let diagnostics, !diagnostics.isEmpty { parts.append(diagnostics) }
        return parts.joined(separator: "\n\n")
    }

    var isCancellation: Bool { kind == .cancelled }

    /// Maps any thrown error into an EngineError for presentation.
    static func wrap(_ error: any Error) -> EngineError {
        if let engine = error as? EngineError { return engine }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return EngineError(kind: .network, rawMessage: ns.localizedDescription)
        }
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileWriteOutOfSpaceError: return EngineError(kind: .diskFull, rawMessage: ns.localizedDescription)
            case NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError, NSFileNoSuchFileError:
                return EngineError(kind: .outputNotWritable, rawMessage: ns.localizedDescription)
            default: break
            }
        }
        return EngineError(kind: .unknown, rawMessage: ns.localizedDescription)
    }
}
