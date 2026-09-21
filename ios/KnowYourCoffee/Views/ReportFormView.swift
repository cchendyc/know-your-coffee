import PhotosUI
import SwiftUI
import UIKit

// Community report, styled after the Figma report-form redesign (frame
// "3 · Report an update — mobile") and mirroring web ReportForm.tsx:
// photo capture that autofills a section, a Gear card, collapsible Beans
// and More cards, chip-based enums, and a section-count submit button.

// MARK: - Suggestion lists (mirror web/src/labels.ts)

private let sourceOptions: [BeanSource] = [
    .inHouseRoast, .localRoaster, .nationalRoaster, .multiRoaster, .privateLabel, .distributor,
]
private let brandOptions = MachineBrand.allCases.filter { $0 != .unknown && $0 != .other }
private let drinkSuggestions = [
    "Espresso", "Latte", "Cappuccino", "Mocha", "Matcha latte",
    "Chai latte", "Drip", "Pour over", "Cold brew", "Hojicha",
]
private let milkSuggestions = [
    "Straus", "Clover", "Oatly", "Minor Figures", "Califia Farms", "Pacific", "Milkadamia",
]
private let originSuggestions = [
    "Ethiopia", "Colombia", "Brazil", "Guatemala", "Kenya", "Indonesia", "Honduras", "Peru",
]
private let fermentSuggestions = [
    "Anaerobic", "Carbonic maceration", "Co-ferment", "Thermal shock",
    "Extended ferment", "Lactic", "Koji", "Yeast inoculated",
]
private let coffeeTypeOptions = [("SINGLE_ORIGIN", "Single origin"), ("BLEND", "Blend")]
private let processOptions = [
    ("WASHED", "Washed"), ("NATURAL", "Natural"), ("HONEY", "Honey"),
    ("WET_HULLED", "Wet-hulled"), ("OTHER", "Other"),
]
private let roastOptions = [("LIGHT", "Light"), ("MEDIUM", "Medium"), ("DARK", "Dark")]

// MARK: - Drafts

private struct MachineDraft: Identifiable {
    let id = UUID()
    var brand: MachineBrand?
    var model = ""
}

private struct GrinderDraft: Identifiable {
    let id = UUID()
    var brand = ""
    var model = ""
}

private struct CoffeeDraft: Identifiable {
    let id = UUID()
    var name = ""
    var type: String?
    var origins: [String] = []
    var addingOrigin = false
    var customOrigin = ""
    var process: String?
    var roast: String?
    var ferment: String?
    var varieties = ""
    var tastingNotes = ""
    var detailOpen = false
}

private struct DrinkDraft: Identifiable {
    var id: String { name }
    let name: String
    var price = ""
}

private struct PhotoEntry: Identifiable {
    let id = UUID()
    let kind: String // MACHINE / MENU / VIBE
    let dataURL: String
    let image: UIImage

    var kindLabel: String {
        ["MACHINE": "Machine", "MENU": "Menu", "VIBE": "Vibe"][kind] ?? kind
    }
}

// MARK: - Form

struct ReportFormView: View {
    let shop: CoffeeShop
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var machines: [MachineDraft] = [MachineDraft()]
    @State private var grinders: [GrinderDraft] = [GrinderDraft()]
    @State private var beanSource: BeanSource?
    @State private var roaster = ""
    @State private var coffees: [CoffeeDraft] = [CoffeeDraft()]
    @State private var drinks: [DrinkDraft] = []
    @State private var milkBrands: [String] = []
    @State private var customMilk = ""
    @State private var dogFriendly: Bool?
    @State private var wifi: Bool?
    @State private var outdoorSeating: Bool?
    @State private var note = ""

    @State private var photos: [PhotoEntry] = []
    @State private var guess: MachineGuess?
    @State private var usedPhoto = false
    @State private var gearFromPhoto = false
    @State private var menuFromPhoto = false
    @State private var analyzing = false

    @State private var beansOpen = false
    @State private var moreOpen = false
    @State private var saving = false
    @State private var error: String?

    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                captureZone
                if !photos.isEmpty { photoStrip }
                if let guess, guess.machine != .unknown { guessBanner(guess) }
                gearCard
                beansCard
                moreCard
                if let error {
                    Text(error)
                        .font(.kycSecondary)
                        .foregroundStyle(.red)
                }
                submitButton
            }
            .padding(20)
        }
        .background(Color.cream50)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Add a photo", isPresented: $showPhotoOptions) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take photo") { showCamera = true }
            }
            Button("Choose from library") { showLibrary = true }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in Task { await handle(images: [image]) } }
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
                await handle(images: images)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Report an update")
                    .font(.kycPageTitle)
                    .foregroundStyle(Color.ink)
                Text("\(shop.name) · \(shop.city)")
                    .font(.kycSecondary)
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.inkMuted)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Capture zone

    private var captureZone: some View {
        Button {
            showPhotoOptions = true
        } label: {
            VStack(spacing: 3) {
                Text(analyzing ? "Reading your photo…" : "Take a photo")
                    .font(.kycBodyBold)
                    .foregroundStyle(Color.ink)
                Text("Optional — autofills its section below")
                    .font(.kycSecondary)
                    .foregroundStyle(Color.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.crema400.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.crema400, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .disabled(analyzing)
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { photo in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .bottomLeading) {
                                Text(photo.kindLabel)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.cream50)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.espresso900.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                                    .padding(2)
                            }
                        Button {
                            photos.removeAll { $0.id == photo.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.cream50)
                                .frame(width: 16, height: 16)
                                .background(Color.espresso700, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                    }
                }
            }
            .padding(.top, 5)
        }
    }

    private func guessBanner(_ guess: MachineGuess) -> some View {
        Text(
            "Looks like a \(guess.machine.label)"
                + (guess.machineModel.map { " \($0)" } ?? "")
                + " (\(Int((guess.confidence * 100).rounded()))% confident)."
        )
        .font(.kycSecondary)
        .foregroundStyle(Color.espresso700)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.cream100, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
    }

    // MARK: Gear

    private var gearCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gear")
                    .font(.kycSection)
                    .foregroundStyle(Color.ink)
                if gearFromPhoto {
                    Text("Filled from your photo — edit anything")
                        .font(.kycMeta)
                        .foregroundStyle(Color.crema500)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel("Espresso machines")
                ForEach($machines) { $machine in
                    HStack(spacing: 8) {
                        brandMenu($machine)
                        TextField("Model (e.g. Linea PB)", text: $machine.model)
                            .fieldChrome()
                        if machines.count > 1 {
                            RemoveButton { machines.removeAll { $0.id == machine.id } }
                        }
                    }
                }
                DashedButton("+ Add another machine") { machines.append(MachineDraft()) }
            }

            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel("Grinders")
                ForEach($grinders) { $grinder in
                    HStack(spacing: 8) {
                        TextField("Brand (e.g. Mahlkönig)", text: $grinder.brand)
                            .fieldChrome()
                        TextField("Model (e.g. EK43)", text: $grinder.model)
                            .fieldChrome()
                        if grinders.count > 1 {
                            RemoveButton { grinders.removeAll { $0.id == grinder.id } }
                        }
                    }
                }
                DashedButton("+ Add grinder") { grinders.append(GrinderDraft()) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(gearFromPhoto ? Color.crema400 : Color.cream200, lineWidth: gearFromPhoto ? 1.5 : 1)
        )
    }

    private func brandMenu(_ machine: Binding<MachineDraft>) -> some View {
        Menu {
            ForEach(brandOptions) { brand in
                Button(brand.label) { machine.wrappedValue.brand = brand }
            }
            Button("Other") { machine.wrappedValue.brand = .other }
            if machine.wrappedValue.brand != nil {
                Divider()
                Button("Clear", role: .destructive) { machine.wrappedValue.brand = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Text(machine.wrappedValue.brand?.label ?? "Brand")
                    .lineLimit(1)
                    .foregroundStyle(
                        machine.wrappedValue.brand == nil ? Color.inkFaint : Color.ink
                    )
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.inkMuted)
            }
            .fieldChrome()
        }
        .buttonStyle(.plain)
    }

    // MARK: Beans

    private var beansCard: some View {
        CollapsibleCard(title: "Beans", open: $beansOpen) {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel("Source")
                FlowLayout(spacing: 6) {
                    ForEach(sourceOptions, id: \.self) { source in
                        Chip(label: source.label, selected: beanSource == source) {
                            beanSource = beanSource == source ? nil : source
                        }
                    }
                }
            }
            // In-house means the shop is the roaster; a name would repeat it.
            if beanSource != .inHouseRoast {
                TextField("Roaster (e.g. Sightglass)", text: $roaster)
                    .fieldChrome()
            }
            ForEach($coffees) { $coffee in
                coffeeCard($coffee)
            }
            DashedButton("+ Add another coffee") { coffees.append(CoffeeDraft()) }
        }
    }

    private func coffeeCard(_ coffee: Binding<CoffeeDraft>) -> some View {
        let c = coffee.wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Coffee name (e.g. Urcunina)", text: coffee.name)
                    .fieldChrome()
                if coffees.count > 1 {
                    RemoveButton { coffees.removeAll { $0.id == c.id } }
                }
            }

            chipRow("Type", options: coffeeTypeOptions, value: c.type) { newType in
                coffee.wrappedValue.type = newType
                // A single origin has one country; keep the first pick.
                if newType == "SINGLE_ORIGIN" {
                    coffee.wrappedValue.origins = Array(c.origins.prefix(1))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel("Origin")
                FlowLayout(spacing: 6) {
                    // Selected customs render alongside the suggestions.
                    let customs = c.origins.filter { !originSuggestions.contains($0) }
                    ForEach(originSuggestions + customs, id: \.self) { origin in
                        Chip(label: origin, selected: c.origins.contains(origin)) {
                            toggleOrigin(coffee, origin)
                        }
                    }
                    Chip(label: "+ country", selected: false) {
                        coffee.wrappedValue.addingOrigin.toggle()
                    }
                }
                if c.addingOrigin {
                    TextField("Country", text: coffee.customOrigin)
                        .fieldChrome()
                        .submitLabel(.done)
                        .onSubmit {
                            let origin = c.customOrigin.trimmingCharacters(in: .whitespaces)
                            guard !origin.isEmpty else { return }
                            toggleOrigin(coffee, origin)
                            coffee.wrappedValue.customOrigin = ""
                            coffee.wrappedValue.addingOrigin = false
                        }
                }
            }

            chipRow("Process", options: processOptions, value: c.process) {
                coffee.wrappedValue.process = $0
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { coffee.wrappedValue.detailOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Rectangle().fill(Color.cream200).frame(height: 1)
                    Text(c.detailOpen ? "Hide detail" : "More detail · roast, ferment, variety, notes")
                        .font(.kycMeta)
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize()
                    Rectangle().fill(Color.cream200).frame(height: 1)
                }
            }
            .buttonStyle(.plain)

            if c.detailOpen {
                chipRow("Roast", options: roastOptions, value: c.roast) {
                    coffee.wrappedValue.roast = $0
                }
                chipRow(
                    "Ferment",
                    options: fermentSuggestions.map { ($0, $0) },
                    value: c.ferment
                ) {
                    coffee.wrappedValue.ferment = $0
                }
                TextField("Varieties, e.g. Gesha, SL28 (comma separated)", text: coffee.varieties)
                    .fieldChrome()
                TextField("Tasting notes, e.g. plum, red grape", text: coffee.tastingNotes)
                    .fieldChrome()
            }
        }
        .padding(12)
        .insetCardStyle()
    }

    private func toggleOrigin(_ coffee: Binding<CoffeeDraft>, _ origin: String) {
        var origins = coffee.wrappedValue.origins
        if origins.contains(origin) {
            origins.removeAll { $0 == origin }
        } else if coffee.wrappedValue.type == "SINGLE_ORIGIN" {
            origins = [origin]
        } else {
            origins.append(origin)
        }
        coffee.wrappedValue.origins = origins
    }

    // One-of chip row; tapping the active value clears it back to unknown.
    private func chipRow(
        _ label: String,
        options: [(String, String)],
        value: String?,
        onChange: @escaping (String?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowLabel(label)
            FlowLayout(spacing: 6) {
                ForEach(options, id: \.0) { option, optionLabel in
                    Chip(label: optionLabel, selected: value == option) {
                        onChange(value == option ? nil : option)
                    }
                }
            }
        }
    }

    // MARK: More (menu, space, note)

    private var moreCard: some View {
        CollapsibleCard(
            title: "More · menu, space, note",
            hint: menuFromPhoto ? "filled from your menu photo" : nil,
            open: $moreOpen
        ) {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel("Menu")
                FlowLayout(spacing: 6) {
                    // Parsed menu items outside the suggestions get chips too.
                    let customs = drinks.map(\.name).filter { !drinkSuggestions.contains($0) }
                    ForEach(drinkSuggestions + customs, id: \.self) { name in
                        Chip(label: name, selected: drinks.contains { $0.name == name }) {
                            toggleDrink(name)
                        }
                    }
                }
                ForEach($drinks) { $drink in
                    HStack(spacing: 8) {
                        Text(drink.name)
                            .font(.kycSecondary)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Spacer()
                        TextField("$", text: $drink.price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                            .fieldChrome()
                        RemoveButton { toggleDrink(drink.name) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel("Milk")
                FlowLayout(spacing: 6) {
                    ForEach(milkSuggestions, id: \.self) { brand in
                        Chip(label: brand, selected: milkBrands.contains(brand)) {
                            if milkBrands.contains(brand) {
                                milkBrands.removeAll { $0 == brand }
                            } else {
                                milkBrands.append(brand)
                            }
                        }
                    }
                }
                TextField("Other milk brands (comma separated)", text: $customMilk)
                    .fieldChrome()
            }

            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel("Space")
                amenityRow("Dog friendly", $dogFriendly)
                amenityRow("Wi-Fi", $wifi)
                amenityRow("Outdoor seating", $outdoorSeating)
            }

            VStack(alignment: .leading, spacing: 6) {
                EyebrowLabel("Note")
                TextField("Anything else?", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .fieldChrome()
            }
        }
    }

    // Yes/No chips; tapping the active answer clears it back to unknown.
    private func amenityRow(_ label: String, _ value: Binding<Bool?>) -> some View {
        HStack {
            Text(label)
                .font(.kycSecondary)
                .foregroundStyle(Color.ink)
            Spacer()
            Chip(label: "Yes", selected: value.wrappedValue == true) {
                value.wrappedValue = value.wrappedValue == true ? nil : true
            }
            Chip(label: "No", selected: value.wrappedValue == false) {
                value.wrappedValue = value.wrappedValue == false ? nil : false
            }
        }
    }

    // MARK: Submit

    private var submitButton: some View {
        let inactive = saving || !hasAnything
        return Button {
            submit()
        } label: {
            Text(submitLabel)
                .font(.kycBodyBold)
                .foregroundStyle(inactive ? Color.inkMuted : Color.inkInverse)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    inactive ? Color.espresso900.opacity(0.08) : Color.espresso700,
                    in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(inactive)
    }

    private var submitLabel: String {
        if saving { return "Submitting…" }
        let n = sectionsUpdated
        return n > 0 ? "Submit — \(n) section\(n > 1 ? "s" : "") updated" : "Submit"
    }

    // MARK: Building the report (mirrors web ReportForm submit)

    private func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // Untouched rows are dropped; a model with no brand goes as OTHER.
    private var builtMachines: [[String: Any]] {
        machines.compactMap { m in
            let model = m.model.trimmingCharacters(in: .whitespaces)
            guard m.brand != nil || !model.isEmpty else { return nil }
            var dict: [String: Any] = ["brand": (m.brand ?? .other).rawValue]
            if !model.isEmpty { dict["model"] = model }
            return dict
        }
    }

    // One grinder on bar; submits as one string, "brand model".
    private var builtGrinders: [String] {
        grinders
            .map { "\($0.brand.trimmingCharacters(in: .whitespaces)) \($0.model.trimmingCharacters(in: .whitespaces))"
                .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // Untouched cards are dropped, so a lone empty card submits nothing.
    private var builtCoffees: [[String: Any]] {
        coffees.compactMap { c in
            let name = c.name.trimmingCharacters(in: .whitespaces)
            let varieties = split(c.varieties)
            let notes = split(c.tastingNotes)
            let touched = !name.isEmpty || c.type != nil || !c.origins.isEmpty
                || c.process != nil || c.ferment != nil || c.roast != nil
                || !varieties.isEmpty || !notes.isEmpty
            guard touched else { return nil }
            var dict: [String: Any] = [
                "origins": c.origins, "varieties": varieties, "tastingNotes": notes,
            ]
            if !name.isEmpty { dict["name"] = name }
            if let type = c.type { dict["type"] = type }
            if let process = c.process { dict["process"] = process }
            if let ferment = c.ferment { dict["fermentation"] = ferment }
            if let roast = c.roast { dict["roastLevel"] = roast }
            return dict
        }
    }

    private var builtDrinks: [[String: Any]] {
        drinks.compactMap { d in
            var dict: [String: Any] = ["name": d.name]
            if let price = Double(d.price) { dict["price"] = price }
            return dict
        }
    }

    private var allMilk: [String] { milkBrands + split(customMilk) }

    private var sectionsUpdated: Int {
        [
            !builtMachines.isEmpty || !builtGrinders.isEmpty,
            beanSource != nil || !roaster.trimmingCharacters(in: .whitespaces).isEmpty || !builtCoffees.isEmpty,
            !builtDrinks.isEmpty || !allMilk.isEmpty,
            dogFriendly != nil || wifi != nil || outdoorSeating != nil
                || !note.trimmingCharacters(in: .whitespaces).isEmpty,
        ].filter { $0 }.count
    }

    private var hasAnything: Bool { sectionsUpdated > 0 || !photos.isEmpty }

    private func toggleDrink(_ name: String) {
        if drinks.contains(where: { $0.name == name }) {
            drinks.removeAll { $0.name == name }
        } else {
            drinks.append(DrinkDraft(name: name))
        }
    }

    private func mergeDrinks(_ items: [DrinkItem]) {
        let existing = Set(drinks.map { $0.name.lowercased() })
        for item in items where !existing.contains(item.name.lowercased()) {
            drinks.append(DrinkDraft(name: item.name, price: item.price.map { String($0) } ?? ""))
        }
    }

    // Route each photo to the section it fills: machine → Gear, menu →
    // More (auto-expanded), anything else joins the gallery as VIBE.
    @MainActor
    private func handle(images: [UIImage]) async {
        analyzing = true
        error = nil
        for image in images {
            guard let data = image.reportDataURL() else { continue }
            do {
                let result = try await CoffeeAPI.identifyMachine(imageBase64: data)
                if result.machine != .unknown {
                    photos.append(PhotoEntry(kind: "MACHINE", dataURL: data, image: image))
                    guess = result
                    // Fill the first untouched machine row, or add a new one.
                    if let idx = machines.firstIndex(where: { $0.brand == nil && $0.model.isEmpty }) {
                        machines[idx].brand = result.machine
                        machines[idx].model = result.machineModel ?? ""
                    } else {
                        var draft = MachineDraft()
                        draft.brand = result.machine
                        draft.model = result.machineModel ?? ""
                        machines.append(draft)
                    }
                    gearFromPhoto = true
                    usedPhoto = true
                    continue
                }
                let items = try await CoffeeAPI.parseMenu(imageBase64: data)
                if !items.isEmpty {
                    photos.append(PhotoEntry(kind: "MENU", dataURL: data, image: image))
                    mergeDrinks(items)
                    menuFromPhoto = true
                    moreOpen = true
                    usedPhoto = true
                    continue
                }
                photos.append(PhotoEntry(kind: "VIBE", dataURL: data, image: image))
            } catch {
                self.error = error.localizedDescription
            }
        }
        analyzing = false
    }

    private func submit() {
        saving = true
        error = nil

        var input: [String: Any?] = [
            "shopId": shop.id,
            "source": usedPhoto ? "PHOTO" : "TEXT",
        ]
        let machineList = builtMachines
        if !machineList.isEmpty { input["machines"] = machineList }
        if let beanSource { input["beanSource"] = beanSource.rawValue }
        // In-house means the shop is the roaster; a name would repeat it.
        let roasterName = roaster.trimmingCharacters(in: .whitespaces)
        if beanSource != .inHouseRoast, !roasterName.isEmpty { input["roaster"] = roasterName }
        let coffeeList = builtCoffees
        if !coffeeList.isEmpty { input["coffees"] = coffeeList }
        let grinderList = builtGrinders
        if !grinderList.isEmpty { input["grinders"] = grinderList }
        let drinkList = builtDrinks
        if !drinkList.isEmpty { input["drinks"] = drinkList }
        let milk = allMilk
        if !milk.isEmpty { input["milkBrands"] = milk }
        if let dogFriendly { input["dogFriendly"] = dogFriendly }
        if let wifi { input["wifi"] = wifi }
        if let outdoorSeating { input["outdoorSeating"] = outdoorSeating }
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        if !trimmedNote.isEmpty { input["note"] = trimmedNote }

        Task {
            do {
                try await CoffeeAPI.submitReport(input)
                if !photos.isEmpty {
                    try await CoffeeAPI.addShopPhotos(
                        shopID: shop.id,
                        photos: photos.map { ["kind": $0.kind, "data": $0.dataURL] }
                    )
                }
                onSubmitted()
            } catch {
                self.error = error.localizedDescription
                saving = false
            }
        }
    }
}

// MARK: - Design atoms (Figma report form styles)

private struct Chip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.kycMeta)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Color.espresso700 : Color.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : Color.cream200))
                .foregroundStyle(selected ? Color.inkInverse : Color.espresso700)
        }
        .buttonStyle(.plain)
    }
}

private struct RemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.inkMuted)
                .padding(4)
        }
        .buttonStyle(.plain)
    }
}

private struct DashedButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.kycMeta)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous)
                        .stroke(Color.cream200, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
        .buttonStyle(.plain)
    }
}

// Section card that collapses to a single row, per the Figma report modal.
private struct CollapsibleCard<Content: View>: View {
    let title: String
    var hint: String?
    @Binding var open: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.kycSection)
                        .foregroundStyle(open ? Color.ink : Color.inkMuted)
                    Spacer()
                    if let hint {
                        Text(hint)
                            .font(.kycMeta)
                            .foregroundStyle(Color.crema500)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkMuted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(open ? Color.crema400 : Color.cream200)
        )
    }
}

// Input chrome matching the Figma fields: white, cream border, radius 12.
private struct FieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.kycSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KYCRadius.control, style: .continuous).stroke(Color.cream200))
    }
}

extension View {
    fileprivate func fieldChrome() -> some View { modifier(FieldChrome()) }
}

extension UIImage {
    // Downscale to ~1000px and encode as a JPEG data URL, matching the
    // web client's downscaleImage() so backend vision costs stay flat.
    fileprivate func reportDataURL(maxDimension: CGFloat = 1000) -> String? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }
}

// Camera capture for the photo door; the library path uses PhotosPicker.
private struct CameraPicker: UIViewControllerRepresentable {
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

// Ownership claim: a note with evidence, resolved later by an admin.
struct ClaimShopSheet: View {
    let shop: CoffeeShop

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var submitting = false
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "How can we verify you own \(shop.name)? A link, your role…",
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                } footer: {
                    Text("An admin reviews claims. Once approved, you're shown as the verified owner.")
                }
                if let result {
                    Section { Text(result).font(.kycSecondary).foregroundStyle(Color.savedGreen) }
                }
                if let error {
                    Section { Text(error).font(.kycSecondary).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Claim \(shop.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarTextButton(label: result == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else if result == nil {
                        ToolbarTextButton(label: "Claim", weight: .semibold) { submit() }
                    }
                }
            }
        }
    }

    private func submit() {
        submitting = true
        Task {
            do {
                let claim = try await CoffeeAPI.claimShop(shopID: shop.id, note: note)
                result = claim.status == "PENDING"
                    ? "Claim submitted — pending review."
                    : "Claim status: \(claim.status.lowercased())."
            } catch {
                self.error = error.localizedDescription
            }
            submitting = false
        }
    }
}
