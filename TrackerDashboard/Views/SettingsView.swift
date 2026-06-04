import SwiftUI

struct SettingsView: View {
    @Environment(SyncController.self) private var sync
    @State private var settings = AppSettings.shared
    @State private var token = AppSettings.shared.apiToken

    var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    TextField("Base URL", text: $settings.apiBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    SecureField("API token", text: $token)
                        .onSubmit { settings.apiToken = token }
                    Button("Save token") {
                        settings.apiToken = token
                    }
                }

                Section("Sheet") {
                    TextField("Spreadsheet ID", text: $settings.spreadsheetID)
                        .textInputAutocapitalization(.never)
                }

                Section("Refresh") {
                    Stepper("Every \(settings.refreshIntervalMinutes) minutes", value: $settings.refreshIntervalMinutes, in: 5...240, step: 5)
                    Button("Force refresh") {
                        Task { await sync.refresh() }
                    }
                }

                Section("Sync Status") {
                    LabeledContent("Last sync", value: sync.syncState.lastSuccessfulSync?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    LabeledContent("Pending writes", value: "\(sync.syncState.pendingOperations.count)")
                    LabeledContent("Cached open tasks", value: "\(SharedCache.shared.loadSnapshot()?.openTasks.count ?? 0)")
                    if let error = sync.syncState.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
