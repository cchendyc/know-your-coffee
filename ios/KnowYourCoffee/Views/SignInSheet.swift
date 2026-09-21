import AuthenticationServices
import SwiftUI

// The sign-in prompt shown when a signed-out user taps a gated action
// (save, been, report, claim, add shop). Dismisses itself on success.
struct SignInSheet: View {
    var onSignedIn: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Circle()
                            .fill(Color.cream200)
                            .frame(width: 84, height: 84)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color.inkFaint)
                            )
                        Text("Sign in to continue")
                            .font(.kycPageTitle)
                            .foregroundStyle(Color.ink)
                        Text("Saving shops, marking visits, posting updates, and adding shops need an account.")
                            .font(.kycSecondary)
                            .foregroundStyle(Color.inkMuted)
                            .lineSpacing(3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 24)

                    SignInOptions {
                        dismiss()
                        onSignedIn()
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color.cream50)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// Apple, Google, and email-code sign-in buttons with their flows and
// error display. Shared by ProfileView and SignInSheet.
struct SignInOptions: View {
    var onSignedIn: () -> Void = {}

    @State private var auth = AuthStore.shared
    @State private var signingIn = false
    @State private var codeSignIn: CodeSignInMethod?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            appleSignInButton
            googleSignInButton
            codeSignInRow

            if let error {
                Text(error)
                    .font(.kycSecondary)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var appleSignInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let token = String(data: tokenData, encoding: .utf8)
                else {
                    error = "Apple returned no identity token."
                    return
                }
                // Apple provides the name only on first authorization.
                let name = credential.fullName.flatMap {
                    let formatted = PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                    return formatted.isEmpty ? nil : formatted
                }
                signingIn = true
                error = nil
                Task {
                    do {
                        try await auth.signInWithApple(identityToken: token, name: name)
                        onSignedIn()
                    } catch {
                        self.error = error.localizedDescription
                    }
                    signingIn = false
                }
            case .failure(let err):
                if (err as? ASAuthorizationError)?.code != .canceled {
                    error = err.localizedDescription
                }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 46)
        .clipShape(Capsule())
        .padding(.horizontal, 24)
    }

    private var googleSignInButton: some View {
        Button {
            signingIn = true
            error = nil
            Task {
                do {
                    try await auth.signIn()
                    onSignedIn()
                } catch AuthError.cancelled {
                } catch {
                    self.error = error.localizedDescription
                }
                signingIn = false
            }
        } label: {
            Group {
                if signingIn {
                    ProgressView().tint(Color.cream50)
                } else {
                    Label("Sign in with Google", systemImage: "person.badge.key")
                }
            }
            .font(.kycBodyBold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.espresso700, in: Capsule())
            .foregroundStyle(Color.inkInverse)
        }
        .buttonStyle(.plain)
        .disabled(signingIn)
        .padding(.horizontal, 24)
    }

    private var codeSignInRow: some View {
        // Phone stays hidden until an SMS provider (Twilio) is configured.
        Button {
            codeSignIn = .email
        } label: {
            Label("Sign in with email code", systemImage: "envelope")
                .font(.kycBodyBold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().strokeBorder(Color.espresso700, lineWidth: 1.5))
                .foregroundStyle(Color.espresso700)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .sheet(item: $codeSignIn) { method in
            CodeSignInSheet(method: method) {
                codeSignIn = nil
                onSignedIn()
            }
            .presentationDetents([.medium])
        }
    }
}

// Two steps: phone number or email, then the 6-digit code.
struct CodeSignInSheet: View {
    let method: CodeSignInMethod
    let onSignedIn: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var identifier = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var devCode: String?
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var isPhone: Bool { method == .phone }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(
                    codeSent
                        ? "Enter the code we sent to \(identifier)."
                        : isPhone ? "We'll text you a sign-in code." : "We'll email you a sign-in code."
                )
                .font(.kycSecondary)
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                if codeSent {
                    TextField("6-digit code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .focused($focused)
                        .padding(14)
                        .background(Color.cream100, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                    if let devCode {
                        Text("Dev backend, no \(isPhone ? "SMS" : "email") provider. Code: \(devCode)")
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.crema500)
                    }
                } else {
                    TextField(isPhone ? "+1 415 555 0100" : "you@example.com", text: $identifier)
                        .keyboardType(isPhone ? .phonePad : .emailAddress)
                        .textContentType(isPhone ? .telephoneNumber : .emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.title3.weight(.medium))
                        .focused($focused)
                        .padding(14)
                        .background(Color.cream100, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 24)
                }

                if let error {
                    Text(error)
                        .font(.kycSecondary)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button(action: submit) {
                    Group {
                        if busy {
                            ProgressView().tint(Color.cream50)
                        } else {
                            Text(codeSent ? "Sign in" : "Send code")
                        }
                    }
                    .font(.kycBodyBold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.espresso700, in: Capsule())
                    .foregroundStyle(Color.inkInverse)
                }
                .buttonStyle(.plain)
                .disabled(busy || (codeSent ? code.count < 6 : identifier.count < (isPhone ? 7 : 6)))
                .padding(.horizontal, 24)

                if codeSent {
                    Button(isPhone ? "Use a different number" : "Use a different email") {
                        codeSent = false
                        code = ""
                        devCode = nil
                        error = nil
                    }
                    .font(.kycSecondary)
                    .foregroundStyle(Color.inkMuted)
                    .frame(minHeight: 44)
                }

                Spacer()
            }
            .padding(.top, 20)
            .background(Color.cream50)
            .navigationTitle(isPhone ? "Phone sign-in" : "Email sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                if codeSent {
                    try await AuthStore.shared.signIn(method: method, identifier: identifier, code: code)
                    dismiss()
                    onSignedIn()
                } else {
                    devCode = try await AuthStore.shared.startCodeSignIn(method: method, identifier: identifier)
                    codeSent = true
                    code = ""
                }
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
