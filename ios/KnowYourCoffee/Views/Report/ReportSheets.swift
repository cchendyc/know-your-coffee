import SwiftUI

// One sheet per tile. Each saves exactly one report; array fields are edited
// as the visible list and sent whole, because the server replaces arrays.

// MARK: - Shared save plumbing

/// Runs a submit closure, surfaces its error, and pops the sheet on success.
@MainActor
private func perform(
    saving: Binding<Bool>,
    error: Binding<String?>,
    dismiss: DismissAction,
    _ work: @escaping () async throws -> Bool
) {
    saving.wrappedValue = true
    error.wrappedValue = nil
    Task {
        defer { saving.wrappedValue = false }
        do {
            if try await work() { dismiss() }
        } catch let failure {
            error.wrappedValue = failure.localizedDescription
        }
    }
}

private func compact(_ dict: [String: Any?]) -> [String: Any] {
    dict.compactMapValues { $0 }
}

// MARK: - Machine

struct MachineDraft: Identifiable, Hashable {
    let id = UUID()
    var brand: String
    var model: String?
}

struct MachineSheet: View {
    let session: ReportSession
    let options: ReportOptions

    @State private var machines: [MachineDraft]
    @State private var text = ""
    @State private var photos: [CapturedPhoto] = []
    @State private var dirty = false
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(session: ReportSession, options: ReportOptions) {
        self.session = session
        self.options = options
        _machines = State(initialValue: session.shop.knownMachines.map {
            MachineDraft(brand: $0.brand.rawValue, model: $0.model)
        })
    }

    private func display(_ machine: MachineDraft) -> String {
        options.machineDisplay(brand: machine.brand, model: machine.model)
    }

    var body: some View {
        SheetScaffold(canSave: dirty && !machines.isEmpty, saving: saving, error: error, onSave: save) {
            ForEach(machines) { machine in
                EditableRow(title: display(machine)) {
                    machines.removeAll { $0.id == machine.id }
                    dirty = true
                }
            }
            TypeaheadField(
                placeholder: "Add a machine",
                text: $text,
                suggestions: options.machines,
                taken: machines.map(display)
            ) { value in
                let parsed = options.parseMachine(value)
                append(MachineDraft(brand: parsed.brand, model: parsed.model))
                return true
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotoCaptureButton { images in Task { await identify(images) } } label: {
                    Image(systemName: "camera.fill").foregroundStyle(Color.espresso700)
                }
            }
        }
        .onAppear {
            if let pending = session.pendingMachine {
                session.pendingMachine = nil
                append(MachineDraft(brand: pending.guess.machine.rawValue, model: pending.guess.machineModel))
                photos.append(pending.photo)
            }
        }
    }

    private func append(_ draft: MachineDraft) {
        guard !machines.contains(where: { display($0).caseInsensitiveCompare(display(draft)) == .orderedSame }) else { return }
        machines.append(draft)
        dirty = true
    }

    private func identify(_ images: [UIImage]) async {
        guard await session.ensureSignedIn() else { return }
        error = nil
        for image in images {
            guard let data = image.reportDataURL() else { continue }
            guard let guess = try? await CoffeeAPI.identifyMachine(imageBase64: data), guess.machine != .unknown else {
                error = "No machine recognized."
                continue
            }
            append(MachineDraft(brand: guess.machine.rawValue, model: guess.machineModel))
            photos.append(CapturedPhoto(kind: "MACHINE", dataURL: data))
        }
    }

    private func save() {
        let payload = machines.map { compact(["brand": $0.brand, "model": $0.model]) }
        perform(saving: $saving, error: $error, dismiss: dismiss) {
            try await session.submit(.machine, fields: ["machines": payload], photos: photos)
        }
    }
}

// MARK: - Grinder

struct GrinderSheet: View {
    let session: ReportSession
    let options: ReportOptions

    @State private var grinders: [String]
    @State private var text = ""
    @State private var dirty = false
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(session: ReportSession, options: ReportOptions) {
        self.session = session
        self.options = options
        _grinders = State(initialValue: session.shop.grinders)
    }

    var body: some View {
        SheetScaffold(canSave: dirty, saving: saving, error: error, onSave: save) {
            ForEach(grinders, id: \.self) { grinder in
                EditableRow(title: grinder) {
                    grinders.removeAll { $0 == grinder }
                    dirty = true
                }
            }
            TypeaheadField(placeholder: "Add a grinder", text: $text, suggestions: options.grinders, taken: grinders) { value in
                if !grinders.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                    grinders.append(value)
                    dirty = true
                }
                return true
            }
        }
    }

    private func save() {
        perform(saving: $saving, error: $error, dismiss: dismiss) {
            try await session.submit(.grinder, fields: ["grinders": grinders])
        }
    }
}

// MARK: - Roaster

struct RoasterSheet: View {
    let session: ReportSession
    let options: ReportOptions

    @State private var source: String?
    @State private var roaster: String
    private let initialSource: String?
    private let initialRoaster: String
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private static let inHouse = "IN_HOUSE_ROAST"

    init(session: ReportSession, options: ReportOptions) {
        self.session = session
        self.options = options
        let shop = session.shop
        let source = shop.beanSource == .unknown ? nil : shop.beanSource.rawValue
        let roaster = shop.roaster ?? ""
        initialSource = source
        initialRoaster = roaster
        _source = State(initialValue: source)
        _roaster = State(initialValue: roaster)
    }

    private var roasterName: String { roaster.trimmingCharacters(in: .whitespaces) }
    private var asksName: Bool { source != Self.inHouse }
    private var changed: Bool {
        source != initialSource || (asksName && roasterName != initialRoaster)
    }

    var body: some View {
        SheetScaffold(canSave: changed && (source != nil || !roasterName.isEmpty), saving: saving, error: error, onSave: save) {
            DropdownField(placeholder: "Who roasts", options: options.beanSources, selection: $source)
            if asksName {
                TypeaheadField(placeholder: "Roaster", text: $roaster, suggestions: options.roasters)
            }
        }
    }

    private func save() {
        // In-house means the shop is the roaster; a name would repeat it.
        let fields: [String: Any?] = [
            "beanSource": source,
            "roaster": asksName && !roasterName.isEmpty ? roasterName : nil,
        ]
        perform(saving: $saving, error: $error, dismiss: dismiss) {
            try await session.submit(.roaster, fields: fields)
        }
    }
}

// MARK: - Coffee

struct CoffeeDraft: Identifiable, Hashable {
    var id = UUID()
    var roaster = ""
    var name = ""
    var type: String?
    var origins: [String] = []
    var process: String?
    var roastLevel: String?
    var fermentation = ""
    var varieties: [String] = []
    var tastingNotes: [String] = []
    /// False until the editor's Save; drafts backed out of are dropped.
    var saved = false

    init(id: UUID = UUID()) {
        self.id = id
    }

    init(_ coffee: Coffee) {
        saved = true
        roaster = coffee.roaster ?? ""
        name = coffee.name ?? ""
        type = coffee.type
        origins = coffee.origins
        process = coffee.process
        roastLevel = coffee.roastLevel
        fermentation = coffee.fermentation ?? ""
        varieties = coffee.varieties
        tastingNotes = coffee.tastingNotes
    }

    var isEmpty: Bool {
        roaster.trimmingCharacters(in: .whitespaces).isEmpty && name.trimmingCharacters(in: .whitespaces).isEmpty
            && type == nil && origins.isEmpty && process == nil && roastLevel == nil
            && fermentation.trimmingCharacters(in: .whitespaces).isEmpty && varieties.isEmpty && tastingNotes.isEmpty
    }

    func title(_ options: ReportOptions) -> String {
        let parts = [roaster, name].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " — ") }
        return pills(options).first ?? "Coffee"
    }

    func pills(_ options: ReportOptions) -> [String] {
        var out: [String] = []
        if let type { out.append(options.label(in: \.coffeeTypes, for: type) ?? type) }
        out += origins
        if let process { out.append(options.label(in: \.processes, for: process) ?? process) }
        if !fermentation.isEmpty { out.append(fermentation) }
        if let roastLevel { out.append((options.label(in: \.roastLevels, for: roastLevel) ?? roastLevel) + " roast") }
        out += varieties
        return out
    }

    /// CoffeeInput. Empty strings are dropped so they do not overwrite as "".
    var payload: [String: Any] {
        func text(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return compact([
            "name": text(name),
            "roaster": text(roaster),
            "type": type,
            "origins": origins,
            "process": process,
            "fermentation": text(fermentation),
            "roastLevel": roastLevel,
            "varieties": varieties,
            "tastingNotes": tastingNotes,
        ])
    }
}

private struct CoffeeEditTarget: Hashable {
    let id: UUID
}

struct CoffeeListSheet: View {
    let session: ReportSession
    let options: ReportOptions

    @State private var coffees: [CoffeeDraft]
    /// The next "Add a coffee" tap edits this id; the draft joins the list on first edit.
    @State private var nextID = UUID()
    @State private var dirty = false
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(session: ReportSession, options: ReportOptions) {
        self.session = session
        self.options = options
        _coffees = State(initialValue: session.shop.coffees.map(CoffeeDraft.init))
    }

    var body: some View {
        SheetScaffold(canSave: dirty, saving: saving, error: error, onSave: save) {
            ForEach(coffees) { coffee in
                NavigationLink(value: CoffeeEditTarget(id: coffee.id)) {
                    EditableRow(
                        title: coffee.title(options),
                        subtitle: coffee.pills(options).joined(separator: " · ")
                    ) {
                        coffees.removeAll { $0.id == coffee.id }
                        dirty = true
                    }
                }
                .buttonStyle(.plain)
            }
            NavigationLink(value: CoffeeEditTarget(id: nextID)) {
                DashedAddLabel(title: "Add a coffee")
            }
            .buttonStyle(.plain)
        }
        .navigationDestination(for: CoffeeEditTarget.self) { target in
            CoffeeEditSheet(draft: binding(for: target.id), options: options) { dirty = true }
        }
        .onAppear {
            // A draft backed out of before Save leaves nothing behind.
            coffees.removeAll { !$0.saved }
        }
    }

    private func binding(for id: UUID) -> Binding<CoffeeDraft> {
        Binding(
            get: { coffees.first { $0.id == id } ?? CoffeeDraft(id: id) },
            set: { updated in
                if let index = coffees.firstIndex(where: { $0.id == id }) {
                    coffees[index] = updated
                } else {
                    coffees.append(updated)
                    nextID = UUID()
                }
            }
        )
    }

    private func save() {
        let payload = coffees.filter { $0.saved && !$0.isEmpty }.map(\.payload)
        perform(saving: $saving, error: $error, dismiss: dismiss) {
            try await session.submit(.coffee, fields: ["coffees": payload])
        }
    }
}

struct CoffeeEditSheet: View {
    @Binding var draft: CoffeeDraft
    let options: ReportOptions
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var singleOrigin: Bool { draft.type == "SINGLE_ORIGIN" }

    var body: some View {
        SheetScaffold(canSave: !draft.isEmpty, saving: false, error: nil, onSave: {
            draft.saved = true
            onSave()
            dismiss()
        }) {
            TypeaheadField(placeholder: "Roaster", text: $draft.roaster, suggestions: options.roasters)
            TextField("Name", text: $draft.name)
                .fieldChrome()
            SegmentedChoice(options: options.coffeeTypes, selection: $draft.type)
            TokenField(
                placeholder: singleOrigin ? "Origin" : "Origins",
                tokens: $draft.origins,
                suggestions: options.origins,
                limit: singleOrigin ? 1 : nil
            )
            DropdownField(placeholder: "Process", options: options.processes, selection: $draft.process, clearable: true)
            TypeaheadField(placeholder: "Fermentation", text: $draft.fermentation, suggestions: options.fermentations)
            SegmentedChoice(options: options.roastLevels, selection: $draft.roastLevel)
            TokenField(placeholder: "Varieties", tokens: $draft.varieties, suggestions: [])
            TokenField(placeholder: "Tasting notes", tokens: $draft.tastingNotes, suggestions: [])
        }
        .navigationTitle(draft.isEmpty ? "Add a coffee" : draft.title(options))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Menu

struct DrinkDraft: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var price: String

    init(name: String, price: Double?) {
        self.name = name
        self.price = price.map { ShopPageFormat.price($0) } ?? ""
    }

    var payload: [String: Any] {
        compact(["name": name, "price": Double(price.replacingOccurrences(of: "$", with: ""))])
    }
}

struct MenuSheet: View {
    let session: ReportSession
    let options: ReportOptions

    @State private var drinks: [DrinkDraft]
    @State private var text = ""
    @State private var photos: [CapturedPhoto] = []
    @State private var dirty = false
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(session: ReportSession, options: ReportOptions) {
        self.session = session
        self.options = options
        _drinks = State(initialValue: session.shop.drinks.map { DrinkDraft(name: $0.name, price: $0.price) })
    }

    var body: some View {
        SheetScaffold(canSave: dirty, saving: saving, error: error, onSave: save) {
            ForEach($drinks) { $drink in
                EditableRow(title: drink.name) {
                    drinks.removeAll { $0.id == drink.id }
                    dirty = true
                } trailing: {
                    TextField("$", text: $drink.price)
                        .font(.kycSecondary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .onChange(of: drink.price) { _, _ in dirty = true }
                }
            }
            TypeaheadField(placeholder: "Add a drink", text: $text, suggestions: options.drinks, taken: drinks.map(\.name)) { value in
                merge([DrinkItem(name: value, price: nil)])
                return true
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotoCaptureButton { images in Task { await read(images) } } label: {
                    Image(systemName: "camera.fill").foregroundStyle(Color.espresso700)
                }
            }
        }
        .onAppear {
            if let pending = session.pendingMenu {
                session.pendingMenu = nil
                merge(pending.items)
                photos.append(pending.photo)
            }
        }
    }

    /// A photo's price wins over a stale one; names match case-insensitively.
    private func merge(_ items: [DrinkItem]) {
        for item in items {
            if let index = drinks.firstIndex(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
                if let price = item.price { drinks[index].price = ShopPageFormat.price(price) }
            } else {
                drinks.append(DrinkDraft(name: item.name, price: item.price))
            }
        }
        dirty = true
    }

    private func read(_ images: [UIImage]) async {
        guard await session.ensureSignedIn() else { return }
        error = nil
        for image in images {
            guard let data = image.reportDataURL() else { continue }
            guard let items = try? await CoffeeAPI.parseMenu(imageBase64: data), !items.isEmpty else {
                error = "No menu recognized."
                continue
            }
            merge(items)
            photos.append(CapturedPhoto(kind: "MENU", dataURL: data))
        }
    }

    private func save() {
        let payload = drinks.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.payload)
        perform(saving: $saving, error: $error, dismiss: dismiss) {
            try await session.submit(.menu, fields: ["drinks": payload], photos: photos)
        }
    }
}

// MARK: - Milk

struct MilkSheet: View {
    let session: ReportSession
    let options: ReportOptions

    @State private var brands: [String]
    private let initial: [String]
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(session: ReportSession, options: ReportOptions) {
        self.session = session
        self.options = options
        let brands = session.shop.milkBrands
        initial = brands
        _brands = State(initialValue: brands)
    }

    var body: some View {
        SheetScaffold(canSave: brands != initial, saving: saving, error: error, onSave: save) {
            TokenField(placeholder: "Milk brands", tokens: $brands, suggestions: options.milkBrands)
        }
    }

    private func save() {
        perform(saving: $saving, error: $error, dismiss: dismiss) {
            try await session.submit(.milk, fields: ["milkBrands": brands])
        }
    }
}

// MARK: - Space

/// Stepper over the server's amenity list. A tap answers and advances; the
/// last answer saves. "Not sure" sends nothing for that field.
struct SpaceSheet: View {
    let session: ReportSession
    let options: ReportOptions

    @State private var step = 0
    @State private var answers: [String: Bool] = [:]
    @State private var selection: String?
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private static let yes = "yes", no = "no", unsure = "unsure"
    private let choices = [
        ReportOption(value: SpaceSheet.yes, label: "Yes"),
        ReportOption(value: SpaceSheet.no, label: "No"),
        ReportOption(value: SpaceSheet.unsure, label: "Not sure"),
    ]

    private var amenities: [ReportOption] { options.amenities }
    private var current: ReportOption? { amenities.indices.contains(step) ? amenities[step] : nil }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            if let current {
                Text(current.label)
                    .font(.kycPageTitle)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                SegmentedChoice(options: choices, selection: $selection) { picked in
                    answer(picked, for: current)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(amenities.indices, id: \.self) { index in
                    Button {
                        step = index
                        selection = preset(for: amenities[index])
                    } label: {
                        Circle()
                            .fill(index == step ? Color.espresso700 : Color.cream200)
                            .frame(width: 8, height: 8)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if saving { ProgressView() }
            if let error { Text(error).font(.kycMeta).foregroundStyle(.red) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cream50)
        .onAppear { selection = current.flatMap { preset(for: $0) } }
    }

    /// This session's answer, else the shop's current value.
    private func preset(for amenity: ReportOption) -> String? {
        let value = answers[amenity.value] ?? session.shop.amenity(amenity.value)
        return value.map { $0 ? Self.yes : Self.no }
    }

    private func answer(_ picked: String, for amenity: ReportOption) {
        switch picked {
        case Self.yes: answers[amenity.value] = true
        case Self.no: answers[amenity.value] = false
        default: answers.removeValue(forKey: amenity.value)
        }
        if step < amenities.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
            selection = current.flatMap { preset(for: $0) }
        } else {
            save()
        }
    }

    private func save() {
        guard !answers.isEmpty else {
            dismiss()
            return
        }
        let fields: [String: Any?] = answers.mapValues { $0 as Any? }
        perform(saving: $saving, error: $error, dismiss: dismiss) {
            try await session.submit(.space, fields: fields)
        }
    }
}

// MARK: - Something else

/// Reason list comes from the server. NOTE saves a note report; any other
/// value flags the shop through reportShop.
struct ElseSheet: View {
    let session: ReportSession
    let options: ReportOptions

    @State private var reason: String?
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private static let noteReason = "NOTE"

    init(session: ReportSession, options: ReportOptions) {
        self.session = session
        self.options = options
        _reason = State(initialValue: options.reportReasons.first?.value)
    }

    private var isNote: Bool { reason == Self.noteReason }
    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SheetScaffold(
            saveTitle: isNote ? "Save" : "Report",
            canSave: isNote ? !trimmedNote.isEmpty : reason != nil,
            saving: saving,
            error: error,
            onSave: save
        ) {
            DropdownField(placeholder: "Reason", options: options.reportReasons, selection: $reason)
            if isNote {
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(3 ... 8)
                    .fieldChrome()
            }
        }
    }

    private func save() {
        guard let reason else { return }
        perform(saving: $saving, error: $error, dismiss: dismiss) {
            if isNote {
                return try await session.submit(.other, fields: ["note": trimmedNote])
            }
            return try await session.flag(reason: reason)
        }
    }
}
