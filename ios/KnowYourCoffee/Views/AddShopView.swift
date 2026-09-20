import SwiftUI

// Add a shop by Google Places lookup: type-ahead, preview, confirm.
// Mirrors the web AddShopModal flow.
struct AddShopView: View {
    let onAdded: (CoffeeShop) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var suggestions: [PlaceSuggestion] = []
    @State private var preview: PlacePreview?
    @State private var searching = false
    @State private var adding = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    @State private var auth = AuthStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !auth.isSignedIn {
                        signInBanner
                    }
                    searchBox

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let preview {
                        previewCard(preview)
                    } else {
                        ForEach(suggestions) { suggestion in
                            Button {
                                loadPreview(suggestion)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.espresso900)
                                    Text(suggestion.address)
                                        .font(.caption)
                                        .foregroundStyle(Color.espresso500)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.cream50)
            .navigationTitle("Add a coffee shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private var signInBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.key")
                .foregroundStyle(Color.crema500)
            Text("Adding a shop needs a signed-in account.")
                .font(.footnote)
                .foregroundStyle(Color.espresso700)
            Spacer()
            Button("Sign in") {
                Task { try? await auth.signIn() }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(Color.crema400.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var searchBox: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.espresso500.opacity(0.55))
            TextField(auth.isSignedIn ? "Shop name, e.g. Sightglass" : "Sign in to search", text: $query)
                .focused($focused)
                .autocorrectionDisabled()
                .disabled(!auth.isSignedIn)
                .onChange(of: query) { search() }
            if searching { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color.espresso900.opacity(0.05), in: Capsule())
    }

    // Debounced type-ahead; each Places call costs money server-side and needs sign-in.
    private func search() {
        preview = nil
        error = nil
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard auth.isSignedIn, text.count >= 3 else {
            suggestions = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                suggestions = try await CoffeeAPI.searchPlaces(query: text)
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func loadPreview(_ suggestion: PlaceSuggestion) {
        searching = true
        Task {
            defer { searching = false }
            do {
                preview = try await CoffeeAPI.placePreview(placeID: suggestion.placeId)
                if preview == nil { error = "Could not load that place." }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func previewCard(_ preview: PlacePreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let photo = preview.photoUrl, let url = URL(string: photo) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.cream200
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(preview.name)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.espresso900)
                Text("\(preview.address), \(preview.city)")
                    .font(.footnote)
                    .foregroundStyle(Color.espresso500)
            }

            if let existing = preview.existing {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Already listed", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.savedGreen)
                    Button("Open \(existing.name)") {
                        onAdded(existing)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } else if !preview.isCoffeeShop {
                Label("Google doesn't think this is a coffee shop, so it can't be added.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.crema500)
            } else {
                Button {
                    add(preview)
                } label: {
                    Group {
                        if adding {
                            ProgressView().tint(Color.cream50)
                        } else {
                            Text("Add this shop")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.espresso700, in: Capsule())
                    .foregroundStyle(Color.cream50)
                }
                .buttonStyle(.plain)
                .disabled(adding)
            }

            Button("Back to results") {
                self.preview = nil
            }
            .font(.caption)
            .foregroundStyle(Color.espresso500)
            .frame(minHeight: 44)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func add(_ preview: PlacePreview) {
        adding = true
        Task {
            do {
                let shop = try await CoffeeAPI.addShopFromPlace(placeID: preview.placeId)
                onAdded(shop)
            } catch {
                self.error = error.localizedDescription
                adding = false
            }
        }
    }
}
