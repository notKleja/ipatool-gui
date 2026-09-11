import SwiftUI

struct SignInSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model: SignInViewModel?
    @FocusState private var focus: Field?

    private enum Field { case email, password, code }

    var body: some View {
        Group {
            if let model {
                @Bindable var model = model
                VStack(alignment: .leading, spacing: 16) {
                    switch model.step {
                    case .credentials: credentials(model)
                    case .verification: verification(model)
                    }
                }
                .padding(24)
                .frame(width: 420)
                .onChange(of: model.signedInAccount) { _, account in
                    if account != nil { dismiss() }
                }
            } else {
                ProgressView().padding(40)
            }
        }
        .task {
            if model == nil { model = SignInViewModel(auth: appState.auth) }
            focus = .email
        }
        .onDisappear { model?.cancel() }
    }

    private func credentials(_ model: SignInViewModel) -> some View {
        @Bindable var model = model
        return Group {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign in to App Store").font(.title2.weight(.semibold))
                Text("Your credentials go directly to ipatool, which keeps its session in the macOS Keychain.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Form {
                TextField("Apple Account", text: $model.email, prompt: Text("name@example.com"))
                    .textContentType(.username)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .onSubmit { model.submitCredentials() }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, -20)
            .disabled(model.isWorking)
            errorText(model)
            HStack {
                if model.isWorking {
                    ProgressView().controlSize(.small)
                    Text("Preparing authentication… the first sign-in can take a minute.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { model.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("Continue") { model.submitCredentials() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canContinue)
            }
        }
    }

    private func verification(_ model: SignInViewModel) -> some View {
        @Bindable var model = model
        return Group {
            VStack(alignment: .leading, spacing: 4) {
                Text("Verification Code").font(.title2.weight(.semibold))
                Text("Enter the verification code sent to your trusted Apple device.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            TextField("Code", text: $model.verificationCode, prompt: Text("123456"))
                .textContentType(.oneTimeCode)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .code)
                .onSubmit { model.submitVerificationCode() }
                .disabled(model.isWorking)
                .task { focus = .code }
                .accessibilityLabel("Verification code")
            errorText(model)
            HStack {
                if model.isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { model.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("Verify") { model.submitVerificationCode() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canVerify)
            }
        }
    }

    @ViewBuilder
    private func errorText(_ model: SignInViewModel) -> some View {
        if let error = model.error {
            VStack(alignment: .leading, spacing: 2) {
                Label(error.kind.title, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout.weight(.medium))
                Text(error.kind.message).font(.caption).foregroundStyle(.secondary)
                if !error.rawMessage.isEmpty {
                    Text(error.rawMessage).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }
}

#Preview("Credentials") {
    SignInSheet().environment(AppState.preview(signedIn: false))
}

#Preview("Two-factor") {
    SignInSheet().environment(AppState.preview(signedIn: false, mock: MockIPAToolService(fixture: .init(account: nil, requiresTwoFactor: true))))
}
