import PhotosUI
import SwiftUI

// Controls shared by the report sheets. Every option list comes from
// ReportOptions; these views only render what they are handed.

// MARK: - Focus relay

/// Sheets report text-field focus up to the launcher, which grows the sheet.
private struct FieldFocusSinkKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    var fieldFocusSink: (Bool) -> Void {
        get { self[FieldFocusSinkKey.self] }
        set { self[FieldFocusSinkKey.self] = newValue }
    }
}

// MARK: - Chrome

private struct FieldChrome: ViewModifier {
    var active = false

    func body(content: Content) -> some View {
        content
            .font(.kycSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous)
                    .stroke(active ? Color.crema400 : Color.cream200)
            )
    }
}

extension View {
    func fieldChrome(active: Bool = false) -> some View { modifier(FieldChrome(active: active)) }
}

/// Suggestion rows under a focused field.
private struct SuggestionList: View {
    let items: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider().overlay(Color.cream200) }
                Button { onPick(item) } label: {
                    HStack {
                        Text(item).font(.kycSecondary).foregroundStyle(Color.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous).stroke(Color.cream200))
    }
}

/// Prefix matches first, then substring matches; empty query shows the head of the list.
func filterSuggestions(_ suggestions: [String], query: String, excluding taken: [String] = [], limit: Int = 8) -> [String] {
    let takenKeys = Set(taken.map { $0.lowercased() })
    let pool = suggestions.filter { !takenKeys.contains($0.lowercased()) }
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return Array(pool.prefix(limit)) }
    let prefix = pool.filter { $0.range(of: q, options: [.caseInsensitive, .anchored]) != nil }
    let rest = pool.filter { !prefix.contains($0) && $0.localizedCaseInsensitiveContains(q) }
    return Array((prefix + rest).prefix(limit))
}

// MARK: - Typeahead

/// Typeable dropdown for an open list: pick a suggestion or type anything.
/// `onCommit` returns true to clear the field (list adders) or false to keep the value.
struct TypeaheadField: View {
    let placeholder: String
    @Binding var text: String
    let suggestions: [String]
    var taken: [String] = []
    var onCommit: (String) -> Bool = { _ in false }

    @FocusState private var focused: Bool
    @Environment(\.fieldFocusSink) private var focusSink

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { commit(text) }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.inkMuted)
            }
            .fieldChrome(active: focused)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            if focused {
                let items = filterSuggestions(suggestions, query: text, excluding: taken)
                if !items.isEmpty {
                    SuggestionList(items: items) { commit($0) }
                }
            }
        }
        .onChange(of: focused) { _, now in focusSink(now) }
    }

    private func commit(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        text = onCommit(trimmed) ? "" : trimmed
        focused = false
    }
}

// MARK: - Tokens

/// Multi-select with free text: chips above a typeahead.
struct TokenField: View {
    let placeholder: String
    @Binding var tokens: [String]
    let suggestions: [String]
    /// Single-token lists (e.g. a blend's origin count) replace instead of append.
    var limit: Int? = nil

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tokens.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tokens, id: \.self) { token in
                        TokenChip(text: token) { tokens.removeAll { $0 == token } }
                    }
                }
            }
            TypeaheadField(placeholder: placeholder, text: $text, suggestions: suggestions, taken: tokens) { value in
                add(value)
                return true
            }
        }
    }

    private func add(_ value: String) {
        if tokens.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { return }
        if let limit, tokens.count >= limit { tokens.removeFirst(tokens.count - limit + 1) }
        tokens.append(value)
    }
}

struct TokenChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.kycMetaBold).foregroundStyle(Color.espresso700).lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.espresso700)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Color.cream100, in: Capsule())
    }
}

// MARK: - Dropdown

/// Fixed list of 4+ values: a menu that reads as a field.
struct DropdownField: View {
    let placeholder: String
    let options: [ReportOption]
    @Binding var selection: String?
    var clearable = false

    private var label: String? { options.first { $0.value == selection }?.label }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
            if clearable, selection != nil {
                Divider()
                Button("Clear", role: .destructive) { selection = nil }
            }
        } label: {
            HStack(spacing: 8) {
                Text(label ?? placeholder)
                    .foregroundStyle(label == nil ? Color.inkFaint : Color.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.inkMuted)
            }
            .fieldChrome()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented

/// 2–3 values side by side. `onPick` fires on every tap, so steppers can advance.
struct SegmentedChoice: View {
    let options: [ReportOption]
    @Binding var selection: String?
    var onPick: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if index > 0 { Divider().frame(height: 22).overlay(Color.cream200) }
                let picked = option.value == selection
                Button {
                    selection = option.value
                    onPick?(option.value)
                } label: {
                    Text(option.label)
                        .font(.kycSecondaryBold)
                        .foregroundStyle(picked ? Color.inkInverse : Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(picked ? Color.espresso700 : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous).stroke(Color.cream200))
    }
}

// MARK: - Rows

/// A current value with a remove control. Wrap in a NavigationLink to make it editable.
struct EditableRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let onRemove: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.kycSecondaryBold).foregroundStyle(Color.ink).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.kycMeta).foregroundStyle(Color.inkMuted).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.inkFaint)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous).stroke(Color.cream200))
        .contentShape(Rectangle())
    }
}

extension EditableRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, onRemove: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, onRemove: onRemove) { EmptyView() }
    }
}

/// Dashed "add" row; the caller supplies the tap (Button or NavigationLink).
struct DashedAddLabel: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "plus")
            .font(.kycMetaBold)
            .foregroundStyle(Color.inkMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous)
                    .stroke(Color.cream200, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Sheet scaffold

/// Scrolling body plus a pinned Save. One report per sheet.
struct SheetScaffold<Content: View>: View {
    var saveTitle = "Save"
    let canSave: Bool
    let saving: Bool
    let error: String?
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content()
                if let error {
                    Text(error).font(.kycMeta).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.cream50)
        .safeAreaInset(edge: .bottom) {
            Button(action: onSave) {
                Group {
                    if saving {
                        ProgressView().tint(Color.inkInverse)
                    } else {
                        Text(saveTitle).font(.kycSecondaryBold)
                    }
                }
                .foregroundStyle(Color.inkInverse)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    canSave ? Color.espresso700 : Color.cream200,
                    in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave || saving)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.cream50)
        }
    }
}

// MARK: - Photo capture

/// Camera or library, as a bare control. Returns the images to the caller.
struct PhotoCaptureButton<Label: View>: View {
    let onImages: ([UIImage]) -> Void
    @ViewBuilder let label: () -> Label

    @State private var showOptions = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        Button { showOptions = true } label: { label() }
            .buttonStyle(.plain)
            .confirmationDialog("Add a photo", isPresented: $showOptions) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take photo") { showCamera = true }
                }
                Button("Choose from library") { showLibrary = true }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in onImages([image]) }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickerItems, maxSelectionCount: 4, matching: .images)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                pickerItems = []
                Task {
                    var images: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    onImages(images)
                }
            }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
