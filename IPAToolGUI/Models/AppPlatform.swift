import Foundation

/// App Store platform as understood by ipatool. `rawValue` is the CLI token.
enum AppPlatform: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case iPhone = "iphone"
    case iPad = "ipad"
    case appleTV = "appletv"
    case vision = "visionos"
    case mac = "macos"

    var id: String { rawValue }

    var cliToken: String { rawValue }

    var displayName: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .appleTV: "Apple TV"
        case .vision: "Apple Vision"
        case .mac: "Mac"
        }
    }

    var operatingSystemName: String {
        switch self {
        case .iPhone: "iOS"
        case .iPad: "iPadOS"
        case .appleTV: "tvOS"
        case .vision: "visionOS"
        case .mac: "macOS"
        }
    }

    var symbolName: String {
        switch self {
        case .iPhone: "iphone"
        case .iPad: "ipad"
        case .appleTV: "appletv"
        case .vision: "visionpro"
        case .mac: "macbook"
        }
    }

    /// File extension of the package ipatool produces for this platform.
    var packageExtension: String { self == .mac ? "pkg" : "ipa" }

    /// Human-readable package kind, e.g. "IPA" or "PKG".
    var packageKind: String { packageExtension.uppercased() }

    /// visionOS search is capped at 12 results upstream.
    var maximumSearchLimit: Int { self == .vision ? 12 : 200 }
}
