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
    @State private var error: String?
    @State private var versionTaps = 0
    @State private var showDeveloper = false
    @State private var confirmDeleteAccount = false
    @State private var deletingAccount = false
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

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
                        .font(.kycBodyBold)
                        .frame(minHeight: 44)

                        // App Store guideline 5.1.1(v): account deletion in-app.
                        Button("Delete account…") {
                            confirmDeleteAccount = true
                        }
                        .font(.kycSecondary)
                        .foregroundStyle(Color.inkMuted)
                        .frame(minHeight: 44)
                        .disabled(deletingAccount)
                        .confirmationDialog(
                            "Delete your account?",
                            isPresented: $confirmDeleteAccount,
                            titleVisibility: .visible
                        ) {
                            Button("Delete account", role: .destructive) {
                                Task { await deleteAccount() }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Your account, saves, and claims are removed permanently. Updates and photos you contributed stay, without your name.")
                        }
                    } else {
                        signedOutHeader
                        SignInOptions {
                            Task {
                                me = try? await CoffeeAPI.fetchMe()
                                if let me { auth.apply(me) }
                                claims = (try? await CoffeeAPI.fetchMyClaims()) ?? []
                            }
                        }
                    }

                    appearanceSection

                    if let error {
                        Text(error)
                            .font(.kycSecondary)
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
                        .font(.kycMeta)
                        .foregroundStyle(Color.inkFaint)
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
                .font(.kycPageTitle)
                .foregroundStyle(Color.ink)
            if let contact = user.contactLine {
                Text(contact)
                    .font(.kycSecondary)
                    .foregroundStyle(Color.inkMuted)
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
        .cardStyle()
        .padding(.horizontal, 24)
    }

    private var claimsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My claims")
                .font(.kycSection)
                .foregroundStyle(Color.ink)
            ForEach(claims) { claim in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(claim.shop.name)
                            .font(.kycBody)
                            .foregroundStyle(Color.ink)
                        Text(claim.shop.city)
                            .font(.kycSecondary)
                            .foregroundStyle(Color.inkMuted)
                    }
                    Spacer()
                    Text(claim.status.capitalized)
                        .font(.kycMetaBold)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(statusColor(claim.status).opacity(0.12), in: Capsule())
                        .foregroundStyle(statusColor(claim.status))
                }
                .padding(12)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    // System follows iOS light/dark; Light and Dark Roast force a theme.
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance")
                .font(.kycSection)
                .foregroundStyle(Color.ink)
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
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
                .font(.kycPageTitle)
                .foregroundStyle(Color.ink)
            Text("Sign in to save shops, mark where you've been, post reports, and claim your shop.")
                .font(.kycSecondary)
                .foregroundStyle(Color.inkMuted)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 24)
    }

    private func deleteAccount() async {
        deletingAccount = true
        defer { deletingAccount = false }
        do {
            try await auth.deleteAccount()
            me = nil
            claims = []
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(Color.cream200)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.inkFaint)
            )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.kycSection)
                .monospacedDigit()
                .foregroundStyle(Color.ink)
            Text(label)
                .font(.kycMeta)
                .foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
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
                    .font(.kycMeta)
                    .foregroundStyle(Color.inkMuted)
            }
            .padding(.top, 8)
        } label: {
            Label("Developer", systemImage: "hammer")
                .font(.kycSecondary)
                .foregroundStyle(Color.inkMuted)
        }
        .tint(Color.espresso500)
    }
}
#endif
