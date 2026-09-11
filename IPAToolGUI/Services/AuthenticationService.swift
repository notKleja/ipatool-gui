import Foundation
import Observation

enum AuthenticationState: Sendable, Equatable {
    case unknown
    case checking
    case signedOut
    case signedIn(Account)

    var account: Account? {
        if case .signedIn(let account) = self { return account }
        return nil
    }

    var isSignedIn: Bool { account != nil }
}

/// Tracks the ipatool session state. ipatool owns the credentials; this only mirrors `auth info`.
@MainActor
@Observable
final class AuthenticationService {
    private(set) var state: AuthenticationState = .unknown
    private(set) var lastError: EngineError?

    @ObservationIgnored private let service: any IPAToolServing

    init(service: any IPAToolServing) {
        self.service = service
    }

    var account: Account? { state.account }
    var isSignedIn: Bool { state.isSignedIn }

    func refresh() async {
        if case .unknown = state { state = .checking }
        do {
            let account = try await service.accountInfo()
            state = account.map { .signedIn($0) } ?? .signedOut
            lastError = nil
        } catch {
            let engineError = EngineError.wrap(error)
            guard !engineError.isCancellation else { return }
            lastError = engineError.kind == .notAuthenticated ? nil : engineError
            state = .signedOut
        }
    }

    func beginLogin(email: String, password: String) -> any LoginAttempt {
        service.beginLogin(email: email, password: password)
    }

    func didSignIn(_ account: Account) {
        state = .signedIn(account)
        lastError = nil
    }

    /// Revokes ipatool's stored App Store session. Does not touch iCloud or the system's Apple Account.
    func signOut() async throws {
        try await service.revokeAuthentication()
        state = .signedOut
    }

    /// Mark the session invalid after another command reported it expired.
    func noteSessionExpired() {
        state = .signedOut
    }
}
