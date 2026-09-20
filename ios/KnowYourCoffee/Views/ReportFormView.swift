import SwiftUI

// Community report ("update shop info"). Only filled-in fields are sent;
// the backend merges them into the shop, newest report wins.
struct ReportFormView: View {
    let shop: CoffeeShop
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var machines: [Machine] = []
    @State private var newBrand: MachineBrand = .laMarzocco
    @State private var newModel = ""

    @State private var beanSource: BeanSource = .unknown
    @State private var roaster = ""
    @State private var origins = ""
    @State private var grinders = ""
    @State private var milkBrands = ""

    @State private var drinks: [(name: String, price: String)] = []
    @State private var newDrinkName = ""
    @State private var newDrinkPrice = ""

    @State private var dogFriendly: Bool?
    @State private var wifi: Bool?
    @State private var outdoorSeating: Bool?

    @State private var note = ""
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Espresso machines") {
                    ForEach(machines, id: \.self) { machine in
                        Text(machine.display)
                    }
                    .onDelete { machines.remove(atOffsets: $0) }

                    HStack {
                        Picker("", selection: $newBrand) {
                            ForEach(MachineBrand.allCases.filter { $0 != .unknown }) { brand in
                                Text(brand.label).tag(brand)
                            }
                        }
                        .labelsHidden()
                        TextField("Model (optional)", text: $newModel)
                        Button {
                            machines.append(Machine(brand: newBrand, model: newModel.isEmpty ? nil : newModel))
                            newModel = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }

                Section("Beans") {
                    Picker("Source", selection: $beanSource) {
                        Text("Unknown").tag(BeanSource.unknown)
                        ForEach(
                            [BeanSource.inHouseRoast, .localRoaster, .nationalRoaster,
                             .multiRoaster, .privateLabel, .distributor],
                            id: \.self
                        ) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    TextField("Roaster, e.g. Equator", text: $roaster)
                    TextField("Origins, comma-separated", text: $origins)
                }

                Section("Equipment & menu") {
                    TextField("Grinders, e.g. Mahlkönig EK43", text: $grinders)
                    TextField("Milk brands, e.g. Straus, Oatly", text: $milkBrands)

                    ForEach(Array(drinks.enumerated()), id: \.offset) { _, drink in
                        HStack {
                            Text(drink.name)
                            Spacer()
                            if !drink.price.isEmpty { Text("$\(drink.price)") }
                        }
                    }
                    .onDelete { drinks.remove(atOffsets: $0) }

                    HStack {
                        TextField("Drink", text: $newDrinkName)
                        TextField("$", text: $newDrinkPrice)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                        Button {
                            guard !newDrinkName.isEmpty else { return }
                            drinks.append((newDrinkName, newDrinkPrice))
                            newDrinkName = ""
                            newDrinkPrice = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }

                Section("Amenities") {
                    triState("Dog friendly", $dogFriendly)
                    triState("Wi-Fi", $wifi)
                    triState("Outdoor seating", $outdoorSeating)
                }

                Section("Note") {
                    TextField("Anything else worth knowing…", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Update \(shop.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else {
                        Button("Submit") { submit() }
                            .disabled(!hasContent)
                    }
                }
            }
        }
    }

    private func triState(_ label: String, _ value: Binding<Bool?>) -> some View {
        Picker(label, selection: value) {
            Text("Unknown").tag(nil as Bool?)
            Text("Yes").tag(true as Bool?)
            Text("No").tag(false as Bool?)
        }
        .pickerStyle(.segmented)
    }

    private var hasContent: Bool {
        !machines.isEmpty || beanSource != .unknown || !roaster.isEmpty || !origins.isEmpty
            || !grinders.isEmpty || !milkBrands.isEmpty || !drinks.isEmpty
            || dogFriendly != nil || wifi != nil || outdoorSeating != nil
            || !note.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func split(_ text: String) -> [String]? {
        let items = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return items.isEmpty ? nil : items
    }

    private func submit() {
        submitting = true
        error = nil
        var input: [String: Any?] = ["shopId": shop.id, "source": "TEXT"]
        if !machines.isEmpty {
            input["machines"] = machines.map { ["brand": $0.brand.rawValue, "model": $0.model as Any] }
        }
        if beanSource != .unknown { input["beanSource"] = beanSource.rawValue }
        if !roaster.isEmpty { input["roaster"] = roaster }
        if let list = split(origins) { input["beanOrigins"] = list }
        if let list = split(grinders) { input["grinders"] = list }
        if let list = split(milkBrands) { input["milkBrands"] = list }
        if !drinks.isEmpty {
            input["drinks"] = drinks.map { ["name": $0.name, "price": Double($0.price) as Any] }
        }
        if let dogFriendly { input["dogFriendly"] = dogFriendly }
        if let wifi { input["wifi"] = wifi }
        if let outdoorSeating { input["outdoorSeating"] = outdoorSeating }
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        if !trimmedNote.isEmpty { input["note"] = trimmedNote }

        Task {
            do {
                try await CoffeeAPI.submitReport(input)
                onSubmitted()
            } catch {
                self.error = error.localizedDescription
                submitting = false
            }
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
                    Section { Text(result).font(.footnote).foregroundStyle(Color.savedGreen) }
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Claim \(shop.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else if result == nil {
                        Button("Claim") { submit() }
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
