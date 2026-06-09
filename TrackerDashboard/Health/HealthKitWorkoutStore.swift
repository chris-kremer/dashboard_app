import Foundation

#if os(iOS)
import HealthKit

struct HealthWorkoutEntry: Equatable {
    var id: String
    var workoutId: String
    var date: String
    var title: String
    var start: String
    var stop: String
    var segmentIndex: Int
    var segmentCount: Int
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
            .flatMap(Self.entries)
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

    private static func entries(for workout: HKWorkout) -> [HealthWorkoutEntry] {
        let workoutId = workout.uuid.uuidString
        let intervals = activeIntervals(for: workout)
        return intervals.enumerated().map { index, interval in
            HealthWorkoutEntry(
                id: "\(workoutId):segment:\(index + 1)",
                workoutId: workoutId,
                date: Date.trackerDateFormatter.string(from: interval.start),
                title: title(for: workout.workoutActivityType),
                start: Date.trackerTimeFormatter.string(from: interval.start),
                stop: Date.trackerTimeFormatter.string(from: interval.end),
                segmentIndex: index + 1,
                segmentCount: intervals.count
            )
        }
    }

    private static func activeIntervals(for workout: HKWorkout) -> [DateInterval] {
        let events = (workout.workoutEvents ?? [])
            .filter { $0.type == .pause || $0.type == .resume }
            .sorted { $0.dateInterval.start < $1.dateInterval.start }

        guard !events.isEmpty else {
            return [DateInterval(start: workout.startDate, end: workout.endDate)]
        }

        var intervals: [DateInterval] = []
        var activeStart: Date? = workout.startDate

        for event in events {
            let eventDate = min(max(event.dateInterval.start, workout.startDate), workout.endDate)
            switch event.type {
            case .pause:
                if let start = activeStart, eventDate > start {
                    intervals.append(DateInterval(start: start, end: eventDate))
                }
                activeStart = nil
            case .resume:
                if activeStart == nil {
                    activeStart = eventDate
                }
            default:
                break
            }
        }

        if let start = activeStart, workout.endDate > start {
            intervals.append(DateInterval(start: start, end: workout.endDate))
        }

        return intervals.isEmpty ? [DateInterval(start: workout.startDate, end: workout.endDate)] : intervals
    }
}
#endif
