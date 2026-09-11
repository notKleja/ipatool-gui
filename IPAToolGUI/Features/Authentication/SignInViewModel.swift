import Foundation
import Observation

@MainActor
@Observable
final class SignInViewModel {
    enum Step: Equatable {
        case credentials
        case verification
    }

    var email = ""
    var password = ""
    var verificationCode = ""
    private(set) var step: Step = .credentials
    private(set) var isWorking = false
    private(set) var error: EngineError?
    private(set) var signedInAccount: Account?

    @ObservationIgnored private let auth: AuthenticationService
    @ObservationIgnored private var attempt: (any LoginAttempt)?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(auth: AuthenticationService) {
        self.auth = auth
    }

    var canContinue: Bool {
        !isWorking && email.trimmingCharacters(in: .whitespaces).contains("@") && !password.isEmpty
    }

    var canVerify: Bool {
        !isWorking && verificationCode.trimmingCharacters(in: .whitespaces).count >= 4
    }

    func submitCredentials() {
        guard canContinue else { return }
        let attempt = auth.beginLogin(email: email.trimmingCharacters(in: .whitespaces), password: password)
        // The service now owns the secret; drop our copy as early as possible.
        password = ""
        self.attempt = attempt
        run {
            let outcome = try await attempt.start()
            switch outcome {
            case .signedIn(let account):
                self.finish(with: account)
            case .verificationRequired:
                self.step = .verification
            }
        }
    }

    func submitVerificationCode() {
        guard canVerify, let attempt else { return }
        let code = verificationCode.trimmingCharacters(in: .whitespaces)
        verificationCode = ""
        run {
            let account = try await attempt.submitVerificationCode(code)
            self.finish(with: account)
        }
    }

    func cancel() {
        task?.cancel()
        attempt?.cancel()
        attempt = nil
        password = ""
        verificationCode = ""
        isWorking = false
    }

    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        error = nil
        task = Task {
            defer { isWorking = false }
            do {
                try await body()
            } catch {
                let engineError = EngineError.wrap(error)
                guard !engineError.isCancellation else { return }
                self.error = engineError
                // A failed attempt cannot be resumed; ipatool must be started again.
                self.attempt = nil
                self.step = .credentials
            }
        }
    }

    private func finish(with account: Account) {
        attempt = nil
        signedInAccount = account
        auth.didSignIn(account)
    }
}
