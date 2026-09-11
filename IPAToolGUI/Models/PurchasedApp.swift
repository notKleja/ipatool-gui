import Foundation

/// One page of `ipatool list-purchases`.
struct PurchasedPage: Decodable, Sendable, Equatable {
    let apps: [AppStoreApp]
    let page: Int
    let count: Int
    let totalCount: Int

    init(apps: [AppStoreApp], page: Int, count: Int, totalCount: Int) {
        self.apps = apps
        self.page = page
        self.count = count
        self.totalCount = totalCount
    }

    private enum CodingKeys: String, CodingKey { case apps, page, count, totalCount }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decodeIfPresent([AppStoreApp].self, forKey: .apps) ?? []
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? apps.count
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount) ?? count
    }

    /// Whether another page is expected after this one.
    func hasMore(pageSize: Int) -> Bool {
        page * pageSize < totalCount && !apps.isEmpty
    }
}
