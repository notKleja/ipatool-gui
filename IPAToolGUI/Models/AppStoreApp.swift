import Foundation

/// An app as reported by `ipatool search` / `ipatool list-purchases` (`--format json`).
struct AppStoreApp: Codable, Hashable, Sendable, Identifiable {
    let id: Int64
    let bundleID: String
    let name: String
    let version: String
    let price: Double
    let purchaseDate: Date?

    init(id: Int64, bundleID: String, name: String, version: String, price: Double, purchaseDate: Date? = nil) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.price = price
        self.purchaseDate = purchaseDate
    }

    private enum CodingKeys: String, CodingKey {
        case id, bundleID, name, version, price, purchaseDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        price = try container.decodeIfPresent(Double.self, forKey: .price) ?? 0
        purchaseDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate)
    }

    var isFree: Bool { price <= 0 }

    var displayName: String { name.isEmpty ? bundleID : name }

    var priceDescription: String {
        if isFree { return "Free" }
        return price.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}

struct SearchResponse: Decodable, Sendable {
    let count: Int
    let apps: [AppStoreApp]

    private enum CodingKeys: String, CodingKey { case count, apps }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decodeIfPresent([AppStoreApp].self, forKey: .apps) ?? []
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? apps.count
    }
}
