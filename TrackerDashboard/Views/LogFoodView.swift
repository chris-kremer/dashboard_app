import SwiftUI

struct LogFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncController.self) private var sync
    @State private var mealContext = ""
    @State private var item = ""
    @State private var amount = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var confidence = "reported"
    @State private var time = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Meal (Breakfast / Lunch / Dinner)", text: $mealContext)
                TextField("Item", text: $item)
                TextField("Amount / size", text: $amount)
                TextField("Location", text: $location)
                TextField("Notes", text: $notes, axis: .vertical)
                TextField("Confidence", text: $confidence)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("Log Meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let request = FoodRequest(
                            date: Date.trackerDateFormatter.string(from: Date()),
                            time: Date.trackerTimeFormatter.string(from: time),
                            mealContext: mealContext,
                            item: item,
                            amount: amount.isEmpty ? nil : amount,
                            location: location.isEmpty ? nil : location,
                            notes: notes.isEmpty ? nil : notes,
                            confidence: confidence.isEmpty ? nil : confidence
                        )
                        Task {
                            await sync.logFood(request)
                            dismiss()
                        }
                    }
                    .disabled(item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
