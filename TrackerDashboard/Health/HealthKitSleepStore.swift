import Foundation

#if os(iOS)
import HealthKit

final class HealthKitSleepStore {
    static let shared = HealthKitSleepStore()

    private let store = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else { return }

        try await store.requestAuthorization(toShare: [], read: [sleepType])
    }

    func sleep(for date: Date = Date()) async throws -> HealthSleepEntry? {
        guard isAvailable,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let dayStart = Calendar.current.dateInterval(of: .day, for: date)?.start
        else { return nil }

        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? date
        let queryStart = Calendar.current.date(byAdding: .hour, value: -12, to: dayStart) ?? dayStart
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: dayEnd, options: [.strictEndDate])
        let samples = try await samples(type: sleepType, predicate: predicate)

        let intervals = samples
            .filter(Self.isAsleepSample)
            .compactMap { sample -> HealthSleepInterval? in
                guard sample.endDate > sample.startDate else { return nil }
                return HealthSleepInterval(id: sample.uuid.uuidString, start: sample.startDate, end: sample.endDate)
            }
            .sorted { $0.start < $1.start }

        guard !intervals.isEmpty else { return nil }
        return HealthSleepEntry(
            date: Date.trackerDateFormatter.string(from: dayStart),
            intervals: Self.merged(intervals),
            source: "healthkit",
            syncedAt: Date()
        )
    }

    private func samples(type: HKCategoryType, predicate: NSPredicate) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }
    }

    private static func isAsleepSample(_ sample: HKCategorySample) -> Bool {
        switch sample.value {
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return true
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return true
        default:
            return false
        }
    }

    private static func merged(_ intervals: [HealthSleepInterval]) -> [HealthSleepInterval] {
        intervals.reduce(into: [HealthSleepInterval]()) { result, interval in
            guard let last = result.last else {
                result.append(interval)
                return
            }
            if interval.start <= last.end {
                result[result.count - 1] = HealthSleepInterval(
                    id: "\(last.id)+\(interval.id)",
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                result.append(interval)
            }
        }
    }
}
#endif
