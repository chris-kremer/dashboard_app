import SwiftUI

struct SettingsView: View {
    @Environment(SyncController.self) private var sync
    @Environment(MediaSyncController.self) private var mediaSync
    @State private var settings = AppSettings.shared
    @State private var token = AppSettings.shared.apiToken
    @State private var nudgeStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Refresh") {
                    Stepper("Every \(settings.refreshIntervalMinutes) minutes", value: $settings.refreshIntervalMinutes, in: 5...240, step: 5)
                    Button("Force refresh") {
                        Task {
                            await sync.refresh()
                            await mediaSync.refresh(date: sync.snapshot.date)
                        }
                    }
                }

                Section("Sync Status") {
                    LabeledContent("Last sync", value: sync.syncState.lastSuccessfulSync?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    LabeledContent("Pending writes", value: "\(sync.syncState.pendingOperations.count)")
                    LabeledContent("Today open tasks", value: "\(SharedCache.shared.loadSnapshot()?.todayOpenTasks.count ?? 0)")
                    if let error = sync.syncState.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section("Media Sync") {
                    LabeledContent("Last media sync", value: mediaSync.snapshot.fetchedAt == .distantPast ? "Never" : mediaSync.snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Media sessions", value: "\(mediaSync.snapshot.sessions?.count ?? mediaSync.snapshot.events.count)")
                    Button("Refresh media") {
                        Task { await mediaSync.refresh(date: sync.snapshot.date) }
                    }
                    if let error = mediaSync.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Toggle("Nudge during free time", isOn: $settings.nudgesEnabled)
                    LabeledContent("First nudge", value: "Immediately")
                    LabeledContent("Repeat", value: "Randomly, about every 2 minutes")
                    Button("Save nudge settings") {
                        Task {
#if os(iOS)
                            await NudgeNotifications.syncRegistrationAndSettings()
                            let error = UserDefaults.standard.string(forKey: NudgeNotifications.registrationErrorKey)
                            nudgeStatus = error ?? "Nudge settings synced"
#else
                            do {
                                try await TrackerAPIClient.shared.updateNudgeSettings(NudgeSettingsRequest(
                                    enabled: settings.nudgesEnabled,
                                    initialDelayMinutes: settings.nudgeInitialDelayMinutes,
                                    repeatIntervalMinutes: settings.nudgeRepeatIntervalMinutes
                                ))
                                nudgeStatus = "Nudge settings synced"
                            } catch {
                                nudgeStatus = error.localizedDescription
                            }
#endif
                        }
                    }
                    Button("Send test nudge") {
                        Task {
                            do {
                                try await TrackerAPIClient.shared.sendTestNudge()
                                nudgeStatus = "Test nudge sent"
                            } catch {
                                nudgeStatus = error.localizedDescription
                            }
                        }
                    }
                    if let nudgeStatus {
                        Text(nudgeStatus)
                            .font(.caption)
                            .foregroundStyle(
                                ["Nudge settings synced", "Test nudge sent"].contains(nudgeStatus)
                                    ? Color.secondary
                                    : Color.red
                            )
                    }
                } header: {
                    Text("Watch Nudges")
                } footer: {
                    Text("Notifications normally tap your Apple Watch when it is worn and your iPhone is locked.")
                }

                Section {
                    NavigationLink {
                        AdvancedSettingsView(settings: settings)
                    } label: {
                        Label("Advanced", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("API, token, and spreadsheet configuration.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct AdvancedSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var token = AppSettings.shared.apiToken

    var body: some View {
        Form {
            Section("API") {
                TextField("Base URL", text: $settings.apiBaseURL)
                    .trackerURLInput()
                SecureField("API token", text: $token)
                    .onSubmit { settings.apiToken = token }
                Button("Save token") {
                    settings.apiToken = token
                }
            }

            Section("Sheet") {
                TextField("Spreadsheet ID", text: $settings.spreadsheetID)
                    .trackerPlainInput()
            }
        }
        .navigationTitle("Advanced")
        .trackerInlineNavigationTitle()
    }
}

private extension View {
    @ViewBuilder
    func trackerURLInput() -> some View {
#if os(iOS)
        self
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
#else
        self
#endif
    }

    @ViewBuilder
    func trackerPlainInput() -> some View {
#if os(iOS)
        self.textInputAutocapitalization(.never)
#else
        self
#endif
    }
}
