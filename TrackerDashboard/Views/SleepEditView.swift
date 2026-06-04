import SwiftUI

struct SleepEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncController.self) private var sync
    @State private var sleepHours = 7.5
    @State private var alarmTime = Date()
    @State private var sleepStart = Date()
    @State private var plannedWake = Date()
    @State private var actualWake = Date()
    @State private var oversleptHours = 0.0

    var body: some View {
        Form {
            Stepper("Sleep \(sleepHours, specifier: "%.1f")h", value: $sleepHours, in: 0...16, step: 0.5)
            Stepper("Overslept \(oversleptHours, specifier: "%.1f")h", value: $oversleptHours, in: 0...8, step: 0.25)
            DatePicker("Alarm", selection: $alarmTime, displayedComponents: .hourAndMinute)
            DatePicker("Sleep start", selection: $sleepStart, displayedComponents: .hourAndMinute)
            DatePicker("Planned wake", selection: $plannedWake, displayedComponents: .hourAndMinute)
            DatePicker("Actual wake", selection: $actualWake, displayedComponents: .hourAndMinute)
            Button("Save") {
                let request = SleepRequest(
                    date: Date.trackerDateFormatter.string(from: Date()),
                    sleepHours: sleepHours,
                    alarmTime: Date.trackerTimeFormatter.string(from: alarmTime),
                    oversleptHours: oversleptHours,
                    sleepStart: Date.trackerTimeFormatter.string(from: sleepStart),
                    plannedWake: Date.trackerTimeFormatter.string(from: plannedWake),
                    actualWake: Date.trackerTimeFormatter.string(from: actualWake)
                )
                Task {
                    await sync.upsertSleep(request)
                    dismiss()
                }
            }
        }
        .navigationTitle("Sleep")
    }
}
