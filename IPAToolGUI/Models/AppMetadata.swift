import Foundation

/// Optional storefront metadata from Apple's public lookup endpoint. Never required for downloads.
struct AppMetadata: Codable, Sendable, Hashable, Identifiable {
    let id: Int64
    let artworkURL: URL?
    let developerName: String?
    let description: String?
    let averageRating: Double?
    let ratingCount: Int?
    let releaseNotes: String?
    let storeURL: URL?
    let screenshotURLs: [URL]
    let genre: String?
    let fileSizeBytes: Int64?
    let minimumOSVersion: String?
    let latestVersion: String?
    let fetchedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case artworkURL = "artworkUrl512"
        case artworkURLSmall = "artworkUrl100"
        case developerName = "artistName"
        case description
        case averageRating = "averageUserRating"
        case ratingCount = "userRatingCount"
        case releaseNotes
        case storeURL = "trackViewUrl"
        case screenshotURLs = "screenshotUrls"
        case ipadScreenshotURLs = "ipadScreenshotUrls"
        case genre = "primaryGenreName"
        case fileSizeBytes
        case minimumOSVersion = "minimumOsVersion"
        case latestVersion = "version"
        case fetchedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        artworkURL = (try? c.decodeIfPresent(URL.self, forKey: .artworkURL))
            ?? (try? c.decodeIfPresent(URL.self, forKey: .artworkURLSmall)) ?? nil
        developerName = try? c.decodeIfPresent(String.self, forKey: .developerName)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        averageRating = try? c.decodeIfPresent(Double.self, forKey: .averageRating)
        ratingCount = try? c.decodeIfPresent(Int.self, forKey: .ratingCount)
        releaseNotes = try? c.decodeIfPresent(String.self, forKey: .releaseNotes)
        storeURL = try? c.decodeIfPresent(URL.self, forKey: .storeURL)
        let shots = (try? c.decodeIfPresent([URL].self, forKey: .screenshotURLs)) ?? nil
        let ipadShots = (try? c.decodeIfPresent([URL].self, forKey: .ipadScreenshotURLs)) ?? nil
        screenshotURLs = (shots?.isEmpty == false ? shots : ipadShots) ?? []
        genre = try? c.decodeIfPresent(String.self, forKey: .genre)
        if let sizeString = try? c.decodeIfPresent(String.self, forKey: .fileSizeBytes) {
            fileSizeBytes = Int64(sizeString)
        } else {
            fileSizeBytes = try? c.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
        }
        minimumOSVersion = try? c.decodeIfPresent(String.self, forKey: .minimumOSVersion)
        latestVersion = try? c.decodeIfPresent(String.self, forKey: .latestVersion)
        fetchedAt = (try? c.decodeIfPresent(Date.self, forKey: .fetchedAt)) ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(artworkURL, forKey: .artworkURL)
        try c.encodeIfPresent(developerName, forKey: .developerName)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(averageRating, forKey: .averageRating)
        try c.encodeIfPresent(ratingCount, forKey: .ratingCount)
        try c.encodeIfPresent(releaseNotes, forKey: .releaseNotes)
        try c.encodeIfPresent(storeURL, forKey: .storeURL)
        try c.encode(screenshotURLs, forKey: .screenshotURLs)
        try c.encodeIfPresent(genre, forKey: .genre)
        try c.encodeIfPresent(fileSizeBytes, forKey: .fileSizeBytes)
        try c.encodeIfPresent(minimumOSVersion, forKey: .minimumOSVersion)
        try c.encodeIfPresent(latestVersion, forKey: .latestVersion)
        try c.encode(fetchedAt, forKey: .fetchedAt)
    }

    init(id: Int64, artworkURL: URL? = nil, developerName: String? = nil, description: String? = nil,
         averageRating: Double? = nil, ratingCount: Int? = nil, releaseNotes: String? = nil,
         storeURL: URL? = nil, screenshotURLs: [URL] = [], genre: String? = nil,
         fileSizeBytes: Int64? = nil, minimumOSVersion: String? = nil, latestVersion: String? = nil,
         fetchedAt: Date = .now) {
        self.id = id
        self.artworkURL = artworkURL
        self.developerName = developerName
        self.description = description
        self.averageRating = averageRating
        self.ratingCount = ratingCount
        self.releaseNotes = releaseNotes
        self.storeURL = storeURL
        self.screenshotURLs = screenshotURLs
        self.genre = genre
        self.fileSizeBytes = fileSizeBytes
        self.minimumOSVersion = minimumOSVersion
        self.latestVersion = latestVersion
        self.fetchedAt = fetchedAt
    }
}

struct LookupResponse: Decodable, Sendable {
    let results: [AppMetadata]

    private enum CodingKeys: String, CodingKey { case results }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Decode leniently: a single malformed entry must not sink the whole batch.
        var nested = try c.nestedUnkeyedContainer(forKey: .results)
        var decoded: [AppMetadata] = []
        while !nested.isAtEnd {
            if let item = try? nested.decode(AppMetadata.self) {
                decoded.append(item)
            } else {
                _ = try? nested.decode(EmptyDecodable.self)
            }
        }
        results = decoded
    }
}

private struct EmptyDecodable: Decodable {}
