import SwiftUI

// Seller application, one coherent stepped flow used by both entries: the
// "Become a seller" card in You, and "Claim this shop" on a shop page (which
// pre-selects the shop and skips the first step).
//
// Verification mirrors how Google Business Profile and Yelp verify owners:
// prove control of a channel already tied to the listing (the shop's phone,
// an email on its domain) or public/physical proof. Review stays manual in
// the support console.
struct SellerApplicationFlow: View {
    var shop: CoffeeShop? = nil

    private enum Step: Int, CaseIterable {
        case shop, role, verify, review
    }

    private enum Method: String, CaseIterable, Identifiable {
        case phone, email, link

        var id: String { rawValue }

        var title: String {
            switch self {
            case .phone: "Call the shop"
            case .email: "Business email"
            case .link: "Public proof"
            }
        }

        var detail: String {
            switch self {
            case .phone: "Our team will call the shop's listed number and ask for you."
            case .email: "An email on the shop's own domain, e.g. you@yourshop.com."
            case .link: "A website, menu, or social page that names you as owner or staff."
            }
        }

        var icon: String {
            switch self {
            case .phone: "phone"
            case .email: "envelope"
            case .link: "link"
            }
        }

        var placeholder: String {
            switch self {
            case .phone: "Shop phone, best time to call, ..."
            case .email: "you@yourshop.com"
            case .link: "yourshop.com/about or instagram.com/yourshop"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .shop
    @State private var selectedShop: CoffeeShop?

    // Shop step
    @State private var query = ""
    @State private var results: [CoffeeShop] = []
    @State private var searching = false

    // Role step
    @State private var businessRole = "Owner"

    // Verify step
    @State private var method: Method = .phone
    @State private var proof = ""
    @State private var link = ""
    @State private var note = ""

    @State private var submitting = false
    @State private var done = false
    @State private var error: String?

    private static let roles: [(name: String, detail: String)] = [
        ("Owner", "You own the business or a stake in it."),
        ("Manager", "You run day-to-day operations."),
        ("Staff", "You work here and act for the owner."),
    ]

    private var steps: [Step] {
        shop == nil ? Step.allCases : [.role, .verify, .review]
    }

    private var currentShop: CoffeeShop? { shop ?? selectedShop }

    private var canContinue: Bool {
        switch step {
        case .shop: currentShop != nil
        case .role: true
        case .verify: hasProof
        case .review: !submitting
        }
    }

    private var hasProof: Bool {
        [proof, link, note].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if done {
                    doneView
                } else {
                    progressBar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            stepHeader
                            stepBody
                            if let error {
                                Text(error)
                                    .font(.kycSecondary)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(20)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    footer
                }
            }
            .background(Color.cream50)
            .navigationTitle("Become a seller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarTextButton(label: done ? "Done" : "Cancel") { dismiss() }
                }
            }
            .task { step = steps[0] }
            .task(id: query) {
                guard shop == nil, step == .shop else { return }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                searching = true
                defer { searching = false }
                results = (try? await CoffeeAPI.fetchShops(
                    search: query.isEmpty ? nil : query, machine: nil, limit: 25, offset: 0
                ).shops) ?? []
            }
        }
    }

    // MARK: Chrome

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.crema500 : Color.cream200)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.kycPageTitle)
                .foregroundStyle(Color.ink)
            Text(subtitle)
                .font(.kycSecondary)
                .foregroundStyle(Color.inkMuted)
        }
    }

    private var title: String {
        switch step {
        case .shop: "Which shop is yours?"
        case .role: "Your role at \(currentShop?.name ?? "the shop")"
        case .verify: "Prove it's really you"
        case .review: "Review your application"
        }
    }

    private var subtitle: String {
        switch step {
        case .shop: "Find your shop in the directory. If it isn't listed, add it from Explore first."
        case .role: "Support may ask the owner to confirm managers and staff."
        case .verify: "Pick the way our team can verify you're connected to the shop."
        case .review: "A person on our support team reviews every application, usually within a few days."
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .shop: shopStep
        case .role: roleStep
        case .verify: verifyStep
        case .review: reviewStep
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != steps[0] {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        step = steps[max(0, (steps.firstIndex(of: step) ?? 0) - 1)]
                    }
                } label: {
                    Text("Back")
                        .font(.kycBodyBold)
                        .foregroundStyle(Color.espresso700)
                        .frame(width: 76, height: 50)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button {
                advance()
            } label: {
                Group {
                    if submitting {
                        ProgressView().tint(Color.inkInverse)
                    } else {
                        Text(step == .review ? "Submit application" : "Continue")
                            .font(.kycBodyBold)
                    }
                }
                .foregroundStyle(Color.inkInverse)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    canContinue ? Color.espresso700 : Color.espresso700.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.cream50)
    }

    private func advance() {
        error = nil
        if step == .review {
            submit()
        } else if let index = steps.firstIndex(of: step), index + 1 < steps.count {
            withAnimation(.snappy(duration: 0.2)) { step = steps[index + 1] }
        }
    }

    // MARK: Steps

    private var shopStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
                TextField("Shop name or city", text: $query)
                    .font(.kycBody)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.espresso900.opacity(0.05), in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))

            if searching && results.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 20)
            } else if results.isEmpty {
                Text("No shops match.")
                    .font(.kycSecondary)
                    .foregroundStyle(Color.inkMuted)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(results) { candidate in
                        selectionCard(
                            selected: selectedShop?.id == candidate.id,
                            action: { selectedShop = candidate }
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name)
                                    .font(.kycBodyBold)
                                    .foregroundStyle(Color.ink)
                                Text([candidate.address, candidate.city].filter { !$0.isEmpty }.joined(separator: ", "))
                                    .font(.kycSecondary)
                                    .foregroundStyle(Color.inkMuted)
                            }
                        }
                    }
                }
            }
        }
    }

    private var roleStep: some View {
        VStack(spacing: 8) {
            ForEach(Self.roles, id: \.name) { role in
                selectionCard(
                    selected: businessRole == role.name,
                    action: { businessRole = role.name }
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(role.name)
                            .font(.kycBodyBold)
                            .foregroundStyle(Color.ink)
                        Text(role.detail)
                            .font(.kycSecondary)
                            .foregroundStyle(Color.inkMuted)
                    }
                }
            }
        }
    }

    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                ForEach(Method.allCases) { candidate in
                    selectionCard(
                        selected: method == candidate,
                        action: { method = candidate }
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: candidate.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.espresso700)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title)
                                    .font(.kycBodyBold)
                                    .foregroundStyle(Color.ink)
                                Text(candidate.detail)
                                    .font(.kycSecondary)
                                    .foregroundStyle(Color.inkMuted)
                            }
                        }
                    }
                }
            }

            inputField(
                label: method == .link ? "Link" : "Where support reaches you",
                placeholder: method.placeholder,
                text: method == .link ? $link : $proof
            )

            inputField(
                label: "Anything else (optional)",
                placeholder: "e.g. I can show a business license or a video of the shop",
                text: $note,
                multiline: true
            )
        }
    }

    private var reviewStep: some View {
        VStack(spacing: 0) {
            reviewRow("Shop", currentShop.map { "\($0.name), \($0.city)" } ?? "—")
            divider
            reviewRow("Role", businessRole)
            divider
            reviewRow("Verify by", method.title)
            if !proof.trimmingCharacters(in: .whitespaces).isEmpty {
                divider
                reviewRow("Contact", proof)
            }
            if !link.trimmingCharacters(in: .whitespaces).isEmpty {
                divider
                reviewRow("Link", link)
            }
            if !note.trimmingCharacters(in: .whitespaces).isEmpty {
                divider
                reviewRow("Note", note)
            }
        }
        .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.card, style: .continuous))
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.savedGreen)
            Text("Application submitted")
                .font(.kycPageTitle)
                .foregroundStyle(Color.ink)
            Text("Support will verify you by \(method.title.lowercased()) and review the application. Once approved, you'll see a brief onboarding and get access to the Seller Hub for \(currentShop?.name ?? "your shop").")
                .font(.kycSecondary)
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.kycBodyBold)
                    .foregroundStyle(Color.inkInverse)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.espresso700, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }

    // MARK: Pieces

    private func selectionCard(
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                content()
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Color.crema500 : Color.inkFaint)
            }
            .padding(14)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous)
                    .strokeBorder(selected ? Color.crema500 : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func inputField(label: String, placeholder: String, text: Binding<String>, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.kycMetaBold)
                .foregroundStyle(Color.inkMuted)
            TextField(placeholder, text: text, axis: multiline ? .vertical : .horizontal)
                .font(.kycBody)
                .lineLimit(multiline ? 2...5 : 1...1)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.kycMetaBold)
                .foregroundStyle(Color.inkMuted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.kycBody)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    private var divider: some View {
        Rectangle().fill(Color.cream200).frame(height: 0.5).padding(.leading, 14)
    }

    private func submit() {
        guard let currentShop else { return }
        submitting = true
        Task {
            do {
                // "Verify by" travels in the note so support knows which
                // channel to use; the schema has no dedicated field.
                let methodNote = "Verify by: \(method.title.lowercased())"
                let extra = note.trimmingCharacters(in: .whitespaces)
                _ = try await CoffeeAPI.claimShop(
                    shopID: currentShop.id,
                    businessRole: businessRole,
                    contact: proof.trimmingCharacters(in: .whitespaces),
                    website: link.trimmingCharacters(in: .whitespaces),
                    note: extra.isEmpty ? methodNote : "\(methodNote). \(extra)"
                )
                done = true
            } catch {
                self.error = error.localizedDescription
            }
            submitting = false
        }
    }
}

#Preview {
    SellerApplicationFlow()
}
