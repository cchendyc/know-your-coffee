import AuthenticationServices
import SwiftUI

// Profile sheet: real account when signed in (Google via ASWebAuthenticationSession),
// sign-in call to action otherwise. Debug builds add a developer section.
struct ProfileView: View {
    let onEndpointChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthStore.shared
    @State private var me: User?
    @State private var claims: [ShopClaim] = []
    @State private var signingIn = false
    @State private var codeSignIn: CodeSignInMethod?
    @State private var error: String?
    @State private var versionTaps = 0
    @State private var showDeveloper = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let user = auth.user {
                        signedInHeader(user)
                        statsRow
                        if !claims.isEmpty { claimsSection }
                        Button("Sign out", role: .destructive) {
                            auth.signOut()
                            me = nil
                            claims = []
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                    } else {
                        signedOutHeader
                        appleSignInButton
                        signInButton
                        codeSignInRow
                    }

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    #if DEBUG
                    if showDeveloper {
                        DeveloperSection(onEndpointChange: onEndpointChange)
                            .padding(.horizontal, 24)
                    }
                    #endif

                    // Debug builds: tapping the version 5 times reveals the
                    // developer section. Invisible otherwise; absent in release.
                    Text("Know Your Coffee \(appVersion)")
                        .font(.caption2)
                        .foregroundStyle(Color.espresso500.opacity(0.5))
                        .padding(.top, 8)
                        .onTapGesture {
                            versionTaps += 1
                            if versionTaps >= 5 { showDeveloper = true }
                        }
                }
                .padding(.bottom, 24)
            }
            .background(Color.cream50)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard auth.isSignedIn else { return }
                me = try? await CoffeeAPI.fetchMe()
                if let me { auth.apply(me) }
                claims = (try? await CoffeeAPI.fetchMyClaims()) ?? []
            }
        }
    }

    // MARK: Signed in

    private func signedInHeader(_ user: User) -> some View {
        VStack(spacing: 12) {
            avatar(user)
            Text(user.name)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.espresso900)
            if let contact = user.contactLine {
                Text(contact)
                    .font(.footnote)
                    .foregroundStyle(Color.espresso500)
            }
        }
        .padding(.top, 24)
    }

    private func avatar(_ user: User) -> some View {
        Group {
            if let picture = user.picture, let url = URL(string: picture) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(Circle())
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(value: me?.savedCount.map(String.init) ?? "…", label: "Saved")
            Divider().frame(height: 28)
            stat(value: me?.beenCount.map(String.init) ?? "…", label: "Been")
        }
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var claimsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My claims")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.espresso900)
            ForEach(claims) { claim in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(claim.shop.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.espresso900)
                        Text(claim.shop.city)
                            .font(.caption)
                            .foregroundStyle(Color.espresso500)
                    }
                    Spacer()
                    Text(claim.status.capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(claim.status).opacity(0.12), in: Capsule())
                        .foregroundStyle(statusColor(claim.status))
                }
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "APPROVED": .savedGreen
        case "REJECTED": .red
        default: .crema500
        }
    }

    // MARK: Signed out

    private var signedOutHeader: some View {
        VStack(spacing: 12) {
            avatarFallback
                .frame(width: 84, height: 84)
                .clipShape(Circle())
            Text("Coffee snob")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.espresso900)
            Text("Sign in to save shops, mark where you've been, post reports, and claim your shop.")
                .font(.footnote)
                .foregroundStyle(Color.espresso500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 24)
    }

    private var signInButton: some View {
        Button {
            signIn()
        } label: {
            Group {
                if signingIn {
                    ProgressView().tint(Color.cream50)
                } else {
                    Label("Sign in with Google", systemImage: "person.badge.key")
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.espresso700, in: Capsule())
            .foregroundStyle(Color.cream50)
        }
        .buttonStyle(.plain)
        .disabled(signingIn)
        .padding(.horizontal, 24)
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
                        me = try? await CoffeeAPI.fetchMe()
                        claims = (try? await CoffeeAPI.fetchMyClaims()) ?? []
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

    private var codeSignInRow: some View {
        // Phone stays hidden until an SMS provider (Twilio) is configured.
        codeSignInOption("Sign in with email code", icon: "envelope", method: .email)
        .padding(.horizontal, 24)
        .sheet(item: $codeSignIn) { method in
            CodeSignInSheet(method: method) {
                codeSignIn = nil
                Task {
                    me = try? await CoffeeAPI.fetchMe()
                    claims = (try? await CoffeeAPI.fetchMyClaims()) ?? []
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func codeSignInOption(_ label: String, icon: String, method: CodeSignInMethod) -> some View {
        Button {
            codeSignIn = method
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().strokeBorder(Color.espresso700, lineWidth: 1.5))
                .foregroundStyle(Color.espresso700)
        }
        .buttonStyle(.plain)
    }

    private func signIn() {
        signingIn = true
        error = nil
        Task {
            do {
                try await auth.signIn()
                me = try? await CoffeeAPI.fetchMe()
                claims = (try? await CoffeeAPI.fetchMyClaims()) ?? []
            } catch AuthError.cancelled {
            } catch {
                self.error = error.localizedDescription
            }
            signingIn = false
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(Color.cream200)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.espresso500.opacity(0.5))
            )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.espresso900)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.espresso500)
        }
        .frame(maxWidth: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

// Two steps: phone number or email, then the 6-digit code.
private struct CodeSignInSheet: View {
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
                .font(.footnote)
                .foregroundStyle(Color.espresso500)
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
                        .font(.caption)
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
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.espresso700, in: Capsule())
                    .foregroundStyle(Color.cream50)
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
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.espresso500)
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

#if DEBUG
// Debug builds only: point the app at a local backend. Never ships.
private struct DeveloperSection: View {
    let onEndpointChange: () -> Void

    @AppStorage(CoffeeAPI.endpointKey) private var apiURL = ""

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                TextField(CoffeeAPI.defaultEndpoint, text: $apiURL)
                    .font(.caption.monospaced())
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.cream100, in: RoundedRectangle(cornerRadius: 10))
                    .onSubmit { onEndpointChange() }
                Text("GraphQL endpoint. Empty = production. Local dev: http://127.0.0.1:4000/graphql")
                    .font(.caption2)
                    .foregroundStyle(Color.espresso500)
            }
            .padding(.top, 8)
        } label: {
            Label("Developer", systemImage: "hammer")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.espresso500)
        }
        .tint(Color.espresso500)
    }
}
#endif
