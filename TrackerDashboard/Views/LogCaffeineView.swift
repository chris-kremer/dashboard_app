import SwiftUI

struct LogCaffeineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncController.self) private var sync
    @State private var label = "coffee"
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label", text: $label)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("Log Coffee")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let request = CaffeineRequest(
                            date: Date.trackerDateFormatter.string(from: Date()),
                            label: label,
                            time: Date.trackerTimeFormatter.string(from: time)
                        )
                        Task {
                            await sync.logCaffeine(request)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
