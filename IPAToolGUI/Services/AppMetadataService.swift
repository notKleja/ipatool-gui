import Foundation

protocol AppMetadataProviding: Sendable {
    func metadata(for id: Int64) async -> AppMetadata?
    func prefetch(ids: [Int64]) async
}

/// Optional enrichment from Apple's public lookup endpoint (`itunes.apple.com/lookup`).
/// Batches IDs, coalesces in-flight requests, caches on disk for a day, and never throws to callers.
actor AppMetadataService: AppMetadataProviding {
    private let session: URLSession
    private let cacheURL: URL?
    private var cache: [Int64: AppMetadata] = [:]
    private var inFlight: [Int64: Task<AppMetadata?, Never>] = [:]
    private var lastRequest = Date.distantPast
    private var saveTask: Task<Void, Never>?
    private let countryProvider: @Sendable () -> String
    private let cacheLifetime: TimeInterval = 24 * 60 * 60
    private let minimumInterval: TimeInterval = 0.3
    private var loaded = false

    init(session: URLSession = .shared, cacheDirectory: URL? = nil, country: @escaping @Sendable () -> String) {
        self.session = session
        self.countryProvider = country
        let directory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dev.ipatoolgui.IPAToolGUI", isDirectory: true)
        cacheURL = directory?.appendingPathComponent("metadata.json")
    }

    func metadata(for id: Int64) async -> AppMetadata? {
        loadIfNeeded()
        if let cached = cache[id], Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime { return cached }
        if let task = inFlight[id] { return await task.value }
        let task = Task<AppMetadata?, Never> { [weak self] in
            guard let self else { return nil }
            let fetched = await self.fetch(ids: [id])
            return fetched[id]
        }
        inFlight[id] = task
        let value = await task.value
        inFlight[id] = nil
        return value
    }

    func prefetch(ids: [Int64]) async {
        loadIfNeeded()
        let missing = ids.filter { id in
            guard inFlight[id] == nil else { return false }
            guard let cached = cache[id] else { return true }
            return Date().timeIntervalSince(cached.fetchedAt) >= cacheLifetime
        }
        guard !missing.isEmpty else { return }
        let batch = Array(Set(missing)).prefix(100)
        let task = Task<[Int64: AppMetadata], Never> { [weak self] in
            await self?.fetch(ids: Array(batch)) ?? [:]
        }
        for id in batch {
            inFlight[id] = Task { await task.value[id] }
        }
        _ = await task.value
        for id in batch { inFlight[id] = nil }
    }

    private func fetch(ids: [Int64]) async -> [Int64: AppMetadata] {
        guard !ids.isEmpty else { return [:] }
        await throttle()
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "id", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "country", value: countryProvider().lowercased()),
        ]
        guard let url = components?.url else { return [:] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [:] }
            let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
            var result: [Int64: AppMetadata] = [:]
            for item in decoded.results {
                result[item.id] = item
                cache[item.id] = item
            }
            scheduleSave()
            return result
        } catch {
            return [:]
        }
    }

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minimumInterval {
            try? await Task.sleep(for: .seconds(minimumInterval - elapsed))
        }
        lastRequest = Date()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let entries = try? JSONDecoder().decode([AppMetadata].self, from: data) else { return }
        for entry in entries where Date().timeIntervalSince(entry.fetchedAt) < cacheLifetime {
            cache[entry.id] = entry
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = Array(cache.values)
        let url = cacheURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let url else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}

/// Preview/test provider that serves canned metadata without networking.
final class MockAppMetadataService: AppMetadataProviding, Sendable {
    private let entries: [Int64: AppMetadata]

    init(entries: [Int64: AppMetadata] = [:]) { self.entries = entries }

    static let previews = MockAppMetadataService(entries: [
        284882215: AppMetadata(id: 284882215, developerName: "Meta Platforms, Inc.", description: "Connect with friends and the world around you.", averageRating: 3.9, ratingCount: 1_200_000, storeURL: URL(string: "https://apps.apple.com/app/id284882215"), genre: "Social Networking"),
        389801252: AppMetadata(id: 389801252, developerName: "Instagram, Inc.", averageRating: 4.6, storeURL: URL(string: "https://apps.apple.com/app/id389801252"), genre: "Photo & Video"),
    ])

    func metadata(for id: Int64) async -> AppMetadata? { entries[id] }
    func prefetch(ids: [Int64]) async {}
}
