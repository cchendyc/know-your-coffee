import SwiftUI

struct SettingsView: View {
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CoffeeAPI.endpointKey) private var apiURL = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(CoffeeAPI.defaultEndpoint, text: $apiURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("GraphQL API URL")
                } footer: {
                    Text(
                        """
                        Leave empty for local development (\(CoffeeAPI.defaultEndpoint), \
                        the simulator reaches uvicorn on your Mac). For production, use \
                        your Render URL, e.g. https://<service>.onrender.com/graphql.
                        """
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.cream50)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        onSave()
                    }
                }
            }
        }
    }
}
