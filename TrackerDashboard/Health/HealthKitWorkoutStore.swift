import Foundation

#if os(iOS)
import HealthKit

struct HealthWorkoutEntry: Equatable {
    var id: String
    var date: String
    var title: String
    var start: String
    var stop: String
}

final class HealthKitWorkoutStore {
    static let shared = HealthKitWorkoutStore()

    private let store = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
    }

    func workouts(for date: Date = Date()) async throws -> [HealthWorkoutEntry] {
        guard isAvailable,
              let dayStart = Calendar.current.dateInterval(of: .day, for: date)?.start
        else { return [] }

        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? date
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd, options: [.strictStartDate])
        let samples = try await workouts(predicate: predicate)
        return samples
            .filter { $0.endDate > $0.startDate }
            .map { workout in
                HealthWorkoutEntry(
                    id: workout.uuid.uuidString,
                    date: Date.trackerDateFormatter.string(from: workout.startDate),
                    title: Self.title(for: workout.workoutActivityType),
                    start: Date.trackerTimeFormatter.string(from: workout.startDate),
                    stop: Date.trackerTimeFormatter.string(from: workout.endDate)
                )
            }
    }

    private func workouts(predicate: NSPredicate) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
    }

    private static func title(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        case .cycling:
            return "Cycling"
        case .traditionalStrengthTraining:
            return "Strength Training"
        case .functionalStrengthTraining:
            return "Functional Strength Training"
        case .coreTraining:
            return "Core Training"
        case .yoga:
            return "Yoga"
        case .swimming:
            return "Swimming"
        case .hiking:
            return "Hiking"
        case .highIntensityIntervalTraining:
            return "HIIT"
        case .elliptical:
            return "Elliptical"
        case .rowing:
            return "Rowing"
        case .soccer:
            return "Soccer"
        case .tennis:
            return "Tennis"
        case .basketball:
            return "Basketball"
        case .other:
            return "Workout"
        default:
            return "Workout"
        }
    }
}
#endif
