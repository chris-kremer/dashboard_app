import SwiftUI

struct WatchSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var token: String = AppSettings.shared.apiToken

    var body: some View {
        Form {
            Section("API") {
                TextField("Base URL", text: $settings.apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save token") {
                    settings.apiToken = token
                }
            }
        }
        .navigationTitle("Settings")
    }
}
