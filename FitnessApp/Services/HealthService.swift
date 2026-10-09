import Foundation
import HealthKit
import Combine

@MainActor final class HealthService: ObservableObject {
    private let store = HKHealthStore()
    @Published var steps: Double?
    @Published var activeCalories: Double?
    @Published var dailyEnergy: [HealthEnergy] = []
    @Published var heartRate: Double?
    @Published var workouts: [HealthWorkout] = []
    @Published var isLoading = false
    @Published var isRequestingAccess = false
    @Published var message = L10n.text("Connect Apple Health in Settings. Read permissions are optional per data type.")
    @Published var refreshedAt: Date?
    @Published var requestedAccess: Bool
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") { requestedAccess = false; return }
        #endif
        requestedAccess = UserDefaults.standard.bool(forKey: "healthAccessRequested")
    }

    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    private var readTypes: Set<HKObjectType> {
        Set<HKObjectType>([
            HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate), HKQuantityType(.bodyMass),
            HKCategoryType(.sleepAnalysis), HKWorkoutType.workoutType()
        ])
    }

    @discardableResult func requestAccess() async -> Bool {
        guard available else { message = L10n.text("Apple Health is unavailable on this device."); return false }
        guard !isRequestingAccess, !isLoading else { return false }
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            requestedAccess = true
            UserDefaults.standard.set(true, forKey: "healthAccessRequested")
            message = L10n.text("Permission request completed. Apple does not reveal read-denial status; missing data may mean no records or no access.")
            return true
        } catch { message = L10n.text("Health permission request failed: %@", String(describing: error.localizedDescription)); return false }
    }

    /// The app is read-only. Watch data is included through HealthKit, with no Watch app required.
    func refresh(into app: AppStore) async {
        guard available, requestedAccess, !isLoading, !isRequestingAccess, app.isReady else { return }
        isLoading = true
        defer { isLoading = false }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let monthStart = Calendar.current.date(byAdding: .day, value: -28, to: start)!
        var errors: [String] = []
        // Reset the live dashboard on each refresh so denied/empty reads never retain stale values.
        steps = nil; activeCalories = nil; heartRate = nil; workouts = []; dailyEnergy = []; app.healthWorkouts = []
        do { steps = try await cumulative(HKQuantityType(.stepCount), unit: .count(), from: start, to: now) }
        catch { errors.append(L10n.text("steps: %@", String(describing: error.localizedDescription))) }
        do { activeCalories = try await cumulative(HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), from: start, to: now) }
        catch { errors.append(L10n.text("active energy: %@", String(describing: error.localizedDescription))) }
        do { dailyEnergy = try await energyDays(from: Calendar.current.date(byAdding: .day, value: -7, to: start)!, to: now) }
        catch { errors.append(L10n.text("active energy: %@", String(describing: error.localizedDescription))) }
        do {
            let samples = try await samples(HKQuantityType(.heartRate), from: start, to: now, limit: 1)
            heartRate = (samples.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        } catch { errors.append(L10n.text("heart rate: %@", String(describing: error.localizedDescription))) }
        do {
            let week = Calendar.current.date(byAdding: .day, value: -13, to: start)!
            let records = try await samples(HKWorkoutType.workoutType(), from: week, to: now)
            workouts = records.compactMap { sample in
                guard let workout = sample as? HKWorkout else { return nil }
                let label: String
                switch workout.workoutActivityType {
                case .badminton: label = L10n.text("Badminton")
                case .traditionalStrengthTraining, .functionalStrengthTraining: label = L10n.text("Strength training")
                case .walking: label = L10n.text("Walking")
                case .running: label = L10n.text("Running")
                default: label = L10n.text("Apple Health workout")
                }
                return HealthWorkout(id: workout.uuid, date: workout.startDate, minutes: workout.duration / 60, label: label,
                    isGym: workout.workoutActivityType == .traditionalStrengthTraining || workout.workoutActivityType == .functionalStrengthTraining,
                    isBadminton: workout.workoutActivityType == .badminton,
                    endDate: workout.endDate,
                    activeCalories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                    source: workout.sourceRevision.source.name)
            }
            app.healthWorkouts = workouts
        } catch { errors.append(L10n.text("workouts: %@", String(describing: error.localizedDescription))) }
        do {
            let records = try await samples(HKQuantityType(.bodyMass), from: monthStart, to: now)
            let weights = records.compactMap { sample -> HealthWeight? in
                guard let sample = sample as? HKQuantitySample else { return nil }
                return HealthWeight(date: sample.startDate, kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)))
            }.sorted { $0.date < $1.date }
            app.importHealthWeights(weights)
        } catch { errors.append(L10n.text("weight: %@", String(describing: error.localizedDescription))) }
        do {
            let sleepType = HKCategoryType(.sleepAnalysis)
            let records = try await samples(sleepType, from: monthStart, to: now, options: [])
            let asleep = Set([HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                              HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                              HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                              HKCategoryValueSleepAnalysis.asleepREM.rawValue])
            let intervals = records.compactMap { sample -> DateInterval? in
                guard let sample = sample as? HKCategorySample, asleep.contains(sample.value), sample.endDate > sample.startDate else { return nil }
                return DateInterval(start: sample.startDate, end: sample.endDate)
            }
            app.importHealthSleep(FitnessLogic.sleepNights(intervals, now: now))
        } catch { errors.append(L10n.text("sleep: %@", String(describing: error.localizedDescription))) }
        refreshedAt = now
        message = errors.isEmpty
            ? L10n.text("Health refreshed. Empty fields mean no readable records. Imported weight and sleep remain locally cached; manual weigh-ins take priority.")
            : L10n.text("Some Health data could not refresh: ") + errors.joined(separator: "; ")
    }

    var usualActiveCalories: Double? {
        let today = Calendar.current.startOfDay(for: Date())
        let values = dailyEnergy.filter { $0.day < today }.map(\.calories)
        return values.count >= 3 ? FitnessLogic.average(values) : nil
    }
    var yesterdayActiveCalories: Double? {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        return dailyEnergy.first { Calendar.current.isDate($0.day, inSameDayAs: yesterday) }?.calories
    }
    private func energyDays(from: Date, to: Date) async throws -> [HealthEnergy] {
        try await withCheckedThrowingContinuation { continuation in
            let type = HKQuantityType(.activeEnergyBurned)
            let query = HKStatisticsCollectionQuery(quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: from, end: to),
                options: .cumulativeSum, anchorDate: from, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                var values: [HealthEnergy] = []
                collection?.enumerateStatistics(from: from, to: to) { statistics, _ in
                    if let energy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()), energy.isFinite, energy >= 0 {
                        values.append(HealthEnergy(day: statistics.startDate, calories: energy))
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private func cumulative(_ type: HKQuantityType, unit: HKUnit, from: Date, to: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit)) }
            }
            store.execute(query)
        }
    }

    private func samples(_ type: HKSampleType, from: Date, to: Date, limit: Int = HKObjectQueryNoLimit, options: HKQueryOptions = .strictStartDate) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: options)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }
}
