import Foundation

/// Opaque identifier of a historical build, as returned by `ipatool list-versions`.
struct ExternalVersionID: RawRepresentable, Codable, Hashable, Sendable, Comparable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// External version IDs are numeric strings that increase over time; compare numerically when possible.
    static func < (lhs: ExternalVersionID, rhs: ExternalVersionID) -> Bool {
        if let l = UInt64(lhs.rawValue), let r = UInt64(rhs.rawValue) { return l < r }
        return lhs.rawValue < rhs.rawValue
    }
}

struct ListVersionsResponse: Decodable, Sendable {
    let externalVersionIdentifiers: [ExternalVersionID]
    let bundleID: String?

    private enum CodingKeys: String, CodingKey { case externalVersionIdentifiers, bundleID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalVersionIdentifiers = try container.decodeIfPresent([ExternalVersionID].self, forKey: .externalVersionIdentifiers) ?? []
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
    }
}

/// Resolved metadata for one historical version (`ipatool get-version-metadata`).
struct AppVersion: Codable, Hashable, Sendable, Identifiable {
    let externalID: ExternalVersionID
    let displayVersion: String
    let releaseDate: Date?

    var id: ExternalVersionID { externalID }

    init(externalID: ExternalVersionID, displayVersion: String, releaseDate: Date?) {
        self.externalID = externalID
        self.displayVersion = displayVersion
        self.releaseDate = releaseDate
    }

    private enum CodingKeys: String, CodingKey {
        case externalID = "externalVersionID"
        case displayVersion, releaseDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        externalID = try container.decode(ExternalVersionID.self, forKey: .externalID)
        displayVersion = try container.decodeIfPresent(String.self, forKey: .displayVersion) ?? ""
        releaseDate = try container.decodeIfPresent(Date.self, forKey: .releaseDate)
    }
}
