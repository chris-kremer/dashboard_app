import Foundation

#if os(iOS)
import HealthKit

final class HealthKitSleepStore {
    static let shared = HealthKitSleepStore()

    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else { return }

        try await store.requestAuthorization(toShare: [], read: [sleepType])
    }

    func startObservingSleepChanges(
        onUpdate: @escaping @Sendable () async -> Void
    ) async throws {
        guard isAvailable,
              observerQuery == nil,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else { return }

        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            Task {
                await onUpdate()
                completion()
            }
        }
        observerQuery = query
        store.execute(query)
        try await store.enableBackgroundDelivery(for: sleepType, frequency: .immediate)
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

        let phases = samples
            .compactMap { sample -> HealthSleepPhaseInterval? in
                guard sample.endDate > sample.startDate,
                      let phase = Self.phase(for: sample)
                else { return nil }
                return HealthSleepPhaseInterval(
                    id: sample.uuid.uuidString,
                    phase: phase,
                    start: sample.startDate,
                    end: sample.endDate
                )
            }
            .sorted { $0.start < $1.start }

        let intervals = phases
            .filter { $0.phase.isAsleep }
            .map { phase in
                HealthSleepInterval(id: phase.id, start: phase.start, end: phase.end)
            }

        guard !intervals.isEmpty else { return nil }
        return HealthSleepEntry(
            date: Date.trackerDateFormatter.string(from: dayStart),
            intervals: Self.merged(intervals),
            source: "healthkit",
            syncedAt: Date(),
            phases: phases
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

    private static func phase(for sample: HKCategorySample) -> HealthSleepPhase? {
        switch sample.value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            return .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return .awake
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return .asleepUnspecified
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            return .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return .rem
        default:
            return nil
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
