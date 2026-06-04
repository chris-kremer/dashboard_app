import SwiftUI

struct LogCaffeineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncController.self) private var sync
    @State private var label = "coffee"
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            Form {
                if !caffeineOptions.isEmpty {
                    Picker("Drink", selection: $label) {
                        ForEach(caffeineOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                TextField("Custom drink", text: $label)
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

    private var caffeineOptions: [String] {
        let options = sync.snapshot.caffeineOptions ?? []
        if options.contains(label) {
            return options
        }
        return label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? options : [label] + options
    }
}
