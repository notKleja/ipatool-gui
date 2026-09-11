import Foundation

/// The App Store account ipatool is currently authenticated as (`ipatool auth info`).
struct Account: Codable, Hashable, Sendable {
    let name: String
    let email: String

    init(name: String, email: String) {
        self.name = name
        self.email = email
    }

    private enum CodingKeys: String, CodingKey { case name, email }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespaces)
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
    }

    var displayName: String { name.isEmpty ? email : name }
}
