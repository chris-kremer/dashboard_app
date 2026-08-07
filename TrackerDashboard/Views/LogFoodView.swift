import SwiftUI

struct LogFoodView: View {
    private static let mealOptions = ["Breakfast", "Lunch", "Dinner", "Snack", "Brunch"]

    @Environment(\.dismiss) private var dismiss
    @Environment(SyncController.self) private var sync
    @State private var mealContext = mealOptions[0]
    @State private var item = ""
    @State private var amount = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var confidence = "reported"
    @State private var time = Date()
    @FocusState private var itemFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Picker("Meal", selection: $mealContext) {
                    ForEach(Self.mealOptions, id: \.self) { meal in
                        Text(meal).tag(meal)
                    }
                }
                TextField("Item", text: $item)
                    .focused($itemFieldFocused)
                if !matchingSuggestions.isEmpty {
                    Section("Previous meals") {
                        ForEach(matchingSuggestions) { suggestion in
                            Button {
                                apply(suggestion)
                            } label: {
                                suggestionRow(suggestion)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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

    private var matchingSuggestions: [FoodSuggestion] {
        guard itemFieldFocused else { return [] }
        let query = normalized(item)
        guard !query.isEmpty else { return [] }
        return Array((sync.snapshot.foodSuggestions ?? [])
            .filter { normalized($0.item).contains(query) }
            .sorted {
                let leftPrefix = normalized($0.item).hasPrefix(query)
                let rightPrefix = normalized($1.item).hasPrefix(query)
                if leftPrefix != rightPrefix { return leftPrefix }
                if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
                return $0.lastUsedDate > $1.lastUsedDate
            }
            .prefix(5))
    }

    private func apply(_ suggestion: FoodSuggestion) {
        item = suggestion.item
        if let priorMeal = suggestion.mealContext,
           let option = Self.mealOptions.first(where: { normalized($0) == normalized(priorMeal) }) {
            mealContext = option
        }
        if let value = suggestion.amount { amount = value }
        if let value = suggestion.location { location = value }
        if let value = suggestion.confidence { confidence = value }
        itemFieldFocused = false
    }

    private func suggestionRow(_ suggestion: FoodSuggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "fork.knife.circle")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.item)
                    .font(.subheadline.weight(.semibold))
                Text(foodSuggestionDetail(suggestion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text("×\(suggestion.useCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func foodSuggestionDetail(_ suggestion: FoodSuggestion) -> String {
        [suggestion.mealContext, suggestion.amount, suggestion.location]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
