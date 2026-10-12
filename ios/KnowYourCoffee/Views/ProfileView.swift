import AuthenticationServices
import SwiftUI

// Me tab / profile sheet: avatar and name, Saved/Been stats, shops (a pending
// claim is another row), Appearance, then Sign out. One account query feeds
// the page; failures show inline with Retry instead of leaving stats on "…".
struct ProfileView: View {
    // True when shown as the Me tab: no Done button, and dismissal is a no-op.
    var isTab = false
    let onEndpointChange: () -> Void

    private enum Load: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthStore.shared
    @State private var account: Account?
    @State private var load: Load = .idle
    // Set when the server rejected a stored token; shown above sign-in.
    @State private var sessionNotice: String?
    @State private var versionTaps = 0
    @State private var showDeveloper = false
    @State private var confirmDeleteAccount = false
    @State private var deletingAccount = false
    @State private var deleteError: String?
    @State private var showBecomeSeller = false
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var shops: [SellerShop] { account?.seller?.shops ?? [] }
    private var pendingClaims: [ShopClaim] {
        (account?.claims ?? []).filter { $0.status == "PENDING" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let user = auth.user {
                        signedInHeader(user)
                        if case .failed(let message) = load { errorBanner(message) }
                        statsRow
                        sellerSection
                    } else {
                        signedOutHeader
                        if let sessionNotice { notice(sessionNotice) }
                        SignInOptions {
                            sessionNotice = nil
                            Task { await loadAccount() }
                        }
                    }

                    appearanceSection

                    if auth.user != nil { accountActions }

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isTab ? .hidden : .automatic, for: .navigationBar)
            .toolbarBackground(Color.cream50, for: .navigationBar)
            .toolbar {
                if !isTab {
                    ToolbarItem(placement: .confirmationAction) {
                        ToolbarTextButton(label: "Done", weight: .semibold) { dismiss() }
                    }
                }
            }
            .refreshable { await loadAccount() }
            .sheet(isPresented: $showBecomeSeller, onDismiss: { Task { await loadAccount() } }) {
                SellerApplicationFlow()
            }
            .task(id: auth.user?.id) { await loadAccount() }
        }
    }

    // MARK: Loading

    private func loadAccount() async {
        guard auth.isSignedIn else {
            account = nil
            load = .idle
            return
        }
        if account == nil { load = .loading }
        do {
            let fetched = try await CoffeeAPI.fetchAccount()
            guard let me = fetched.me else {
                // Token not recognised (server restart, secret rotation, or a
                // token from a different backend). Drop it instead of showing
                // an empty account as if the user owned nothing.
                auth.sessionExpired()
                account = nil
                load = .idle
                sessionNotice = "Your session expired. Sign in again."
                return
            }
            auth.apply(me)
            account = fetched
            load = .loaded
        } catch {
            load = .failed(error.localizedDescription)
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
        .padding(.top, 8)
    }

    private func avatar(_ user: User) -> some View {
        Group {
            if let picture = user.picture, let url = URL(string: picture) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        monogram(user.name)
                    }
                }
            } else {
                monogram(user.name)
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(Circle())
    }

    // Espresso disc with cream initials; the Figma avatar.
    private func monogram(_ name: String) -> some View {
        let initials = name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }.joined().uppercased()
        return Circle()
            .fill(Color.espresso700)
            .overlay(
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.cream50)
            )
    }

    // Each stat opens its list; the feed pins the filter and shows a title.
    private var statsRow: some View {
        HStack(spacing: 0) {
            statLink(value: account?.me?.savedCount, list: .saved)
            Divider().frame(height: 28)
            statLink(value: account?.me?.beenCount, list: .been)
        }
        .padding(.vertical, 14)
        .cardStyle()
        .padding(.horizontal, 24)
    }

    private func statLink(value: Int?, list: ShopStore.ListFilter) -> some View {
        NavigationLink {
            HomeView(embedded: true, pinnedList: list)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.cream50, for: .navigationBar)
        } label: {
            VStack(spacing: 2) {
                Text(statText(value))
                    .font(.kycSection)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                    .redacted(reason: load == .loading && value == nil ? .placeholder : [])
                Text(list.label)
                    .font(.kycMeta)
                    .foregroundStyle(Color.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statText(_ value: Int?) -> String {
        if let value { return String(value) }
        return load == .loading ? "00" : "—"
    }

    // Owned shops, plus a row for each claim still waiting on support.
    @ViewBuilder
    private var sellerSection: some View {
        if !shops.isEmpty || !pendingClaims.isEmpty {
            section(shops.count + pendingClaims.count == 1 ? "Your shop" : "Your shops") {
                ForEach(shops) { shop in
                    NavigationLink {
                        SellerHubView(shops: shops.map(\.owned), selected: shop.owned)
                    } label: {
                        row(
                            icon: "square.grid.2x2",
                            imageURL: shop.photoURL,
                            title: shop.name,
                            subtitle: shop.city,
                            verified: shop.sellerOnboarded,
                            badge: sellerBadge(shop)
                        )
                    }
                    .buttonStyle(.plain)
                }
                ForEach(pendingClaims) { claim in
                    row(
                        icon: "square.grid.2x2",
                        imageURL: claim.shop.photoURL,
                        title: claim.shop.name,
                        subtitle: claim.shop.city,
                        badge: Badge(text: "Pending", tint: .crema500),
                        showsChevron: false
                    )
                }
            }
        } else if load == .loading {
            section("Your shop") {
                row(icon: "square.grid.2x2", title: "Seller Hub", subtitle: "Checking your shops")
                    .redacted(reason: .placeholder)
            }
        } else {
            section("Sell on Know Your Coffee") {
                Button {
                    showBecomeSeller = true
                } label: {
                    row(icon: "storefront", title: "Become a seller", subtitle: "List beans, take orders, ship from your shop")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sellerBadge(_ shop: SellerShop) -> Badge? {
        if !shop.sellerOnboarded { return Badge(text: "Finish setup", tint: .crema500) }
        let open = shop.workload?.toFulfill ?? 0
        return open > 0 ? Badge(text: "\(open) new", tint: .crema500) : nil
    }

    // System follows iOS light/dark; Light and Dark Roast force a theme.
    private var appearanceSection: some View {
        section("Appearance") {
            KYCSegmentedControl(
                options: AppAppearance.allCases,
                selection: Binding(
                    get: { AppAppearance(rawValue: appearanceRaw) ?? .system },
                    set: { appearanceRaw = $0.rawValue }
                ),
                label: { $0.label },
                symbol: { $0.symbol }
            )
        }
    }

    private var accountActions: some View {
        VStack(spacing: 4) {
            Button("Sign out", role: .destructive) {
                auth.signOut()
                account = nil
                load = .idle
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

            if let deleteError {
                Text(deleteError)
                    .font(.kycSecondary)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.kycSection)
                .foregroundStyle(Color.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private struct Badge {
        let text: String
        let tint: Color
    }

    // Icon tile, title (with a seal when verified), subtitle, badge, chevron.
    private func row(icon: String, imageURL: URL? = nil, title: String, subtitle: String, verified: Bool = false, badge: Badge? = nil, showsChevron: Bool = true) -> some View {
        HStack(spacing: 12) {
            shopAvatar(icon: icon, imageURL: imageURL)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.kycBodyBold)
                        .foregroundStyle(Color.ink)
                    if verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.savedGreen)
                            .accessibilityLabel("Verified")
                    }
                }
                Text(subtitle)
                    .font(.kycSecondary)
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let badge {
                Text(badge.text)
                    .font(.kycMetaBold)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(badge.tint.opacity(0.14), in: Capsule())
                    .foregroundStyle(badge.tint)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkFaint)
            }
        }
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
        .contentShape(Rectangle())
    }

    private func shopAvatar(icon: String, imageURL: URL?) -> some View {
        let shape = RoundedRectangle(cornerRadius: KYCRadius.thumb, style: .continuous)
        return Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.espresso700)
                    }
                }
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.espresso700)
            }
        }
        .frame(width: 40, height: 40)
        .background(Color.cream100, in: shape)
        .clipShape(shape)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.crema500)
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't load your account")
                    .font(.kycSecondaryBold)
                    .foregroundStyle(Color.ink)
                Text(message)
                    .font(.kycSecondary)
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            Button("Retry") { Task { await loadAccount() } }
                .font(.kycSecondaryBold)
                .foregroundStyle(Color.espresso700)
        }
        .padding(14)
        .insetCardStyle()
        .padding(.horizontal, 24)
    }

    private func notice(_ message: String) -> some View {
        Text(message)
            .font(.kycSecondary)
            .foregroundStyle(Color.inkMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    // MARK: Signed out

    private var signedOutHeader: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Color.cream200)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.inkFaint)
                )
                .frame(width: 76, height: 76)
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
        .padding(.top, 8)
    }

    private func deleteAccount() async {
        deletingAccount = true
        defer { deletingAccount = false }
        do {
            try await auth.deleteAccount()
            account = nil
            load = .idle
        } catch {
            deleteError = error.localizedDescription
        }
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
