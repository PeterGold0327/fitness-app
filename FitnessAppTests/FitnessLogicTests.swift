import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import FitnessCore
#else
@testable import LeanLog
#endif

final class FitnessLogicTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 14))! }
    private func points(gain: Double, days: Int = 28) -> [WeightPoint] {
        (0..<days).map { index in
            let date = calendar.date(byAdding: .day, value: -index, to: now)!
            return WeightPoint(date: date, kilograms: 63 - Double(index) * gain / 7)
        }
    }
    func testDefaultBreakfastFitsBrief() {
        let meal = FitnessLogic.breakfast()
        XCTAssertEqual(meal.calories, 486.2, accuracy: 0.1)
        XCTAssertTrue((450...550).contains(meal.calories))
        XCTAssertTrue((25...30).contains(meal.protein))
    }
    func testFlatWeightSuggestsIncrease() {
        let trend = FitnessLogic.weightTrend(points(gain: 0), now: now, calendar: calendar)
        XCTAssertEqual(trend.label, "Too slow")
        XCTAssertEqual(trend.calorieAdjustment, 175)
    }
    func testSteadyLeanGainKeepsTargets() {
        let trend = FitnessLogic.weightTrend(points(gain: 0.18), now: now, calendar: calendar)
        XCTAssertEqual(trend.label, "On target")
        XCTAssertEqual(trend.weeklyGain!, 0.18, accuracy: 0.001)
        XCTAssertNil(trend.calorieAdjustment)
    }
    func testRapidGainSuggestsReduction() {
        let trend = FitnessLogic.weightTrend(points(gain: 0.5), now: now, calendar: calendar)
        XCTAssertEqual(trend.label, "Too fast")
        XCTAssertEqual(trend.calorieAdjustment, -125)
    }
    func testFourWeekRateIsNormalizedPerWeek() {
        let trend = FitnessLogic.weightTrend(points(gain: 0.2), now: now, weeks: 4, calendar: calendar)
        XCTAssertEqual(trend.weeklyGain!, 0.2, accuracy: 0.001)
    }
    func testSparseDataDoesNotSuggestTargetChange() {
        let trend = FitnessLogic.weightTrend(Array(points(gain: 0.2).prefix(3)), now: now, calendar: calendar)
        XCTAssertNil(trend.weeklyGain)
        XCTAssertNil(trend.calorieAdjustment)
        XCTAssertNotNil(trend.average)
    }
    func testCalendarWindowsDoNotUseOldWeighIns() {
        let stale = WeightPoint(date: calendar.date(byAdding: .day, value: -40, to: now)!, kilograms: 100)
        let trend = FitnessLogic.weightTrend([stale], now: now, calendar: calendar)
        XCTAssertNil(trend.average)
    }
    func testFutureWeightExcluded() {
        let future = WeightPoint(date: calendar.date(byAdding: .day, value: 2, to: now)!, kilograms: 100)
        let trend = FitnessLogic.weightTrend(points(gain: 0) + [future], now: now, calendar: calendar)
        XCTAssertEqual(trend.average!, 63, accuracy: 0.001)
    }
    func testDuplicateDayUsesLatestValue() {
        let day = calendar.startOfDay(for: now)
        let trend = FitnessLogic.weightTrend([
            WeightPoint(date: day, kilograms: 60),
            WeightPoint(date: day.addingTimeInterval(3600), kilograms: 64)
        ], now: now, calendar: calendar)
        XCTAssertEqual(trend.average, 64)
    }
    func testOverlappingSleepDoesNotDoubleCount() {
        let intervals = [DateInterval(start: now, duration: 8 * 3600),
                         DateInterval(start: now.addingTimeInterval(3600), duration: 6 * 3600)]
        XCTAssertEqual(FitnessLogic.mergedHours(intervals), 8)
    }
    func testSeparateSleepIntervalsSum() {
        let intervals = [DateInterval(start: now, duration: 6 * 3600),
                         DateInterval(start: now.addingTimeInterval(10 * 3600), duration: 3600)]
        XCTAssertEqual(FitnessLogic.mergedHours(intervals), 7)
        XCTAssertEqual(FitnessLogic.mergedHours([]), 0)
    }
    private func performance(weight: Double, rpe: Double = 7, reps: Int = 8, offset: Double = 0) -> ExercisePerformance {
        ExercisePerformance(date: now.addingTimeInterval(offset), weight: weight, sets: 3, reps: reps, targetReps: 8, rpe: rpe)
    }
    func testManageableCompletedSetsSuggestLoadIncrease() {
        XCTAssertTrue(FitnessLogic.progression([performance(weight: 40)]).contains("adding 1–2.5 kg"))
    }
    func testChallengingCompletedSetsSuggestReps() {
        XCTAssertTrue(FitnessLogic.progression([performance(weight: 40, rpe: 9)]).contains("one more rep"))
    }
    func testTwoDropsSuggestRecovery() {
        let history = [performance(weight: 50), performance(weight: 45, offset: 86400), performance(weight: 40, offset: 172800)]
        XCTAssertTrue(FitnessLogic.progression(history).contains("two consecutive"))
    }
    func testMissedRepsDoNotSuggestIncrease() {
        XCTAssertTrue(FitnessLogic.progression([performance(weight: 40, reps: 5)]).contains("Maintain"))
    }
    func testHeavyLegWarningRequiresNearbyBadminton() {
        XCTAssertNotNil(FitnessLogic.legWarning(gymDate: now, heavyLegs: true, badmintonDates: [now.addingTimeInterval(86400)]))
        XCTAssertNil(FitnessLogic.legWarning(gymDate: now, heavyLegs: false, badmintonDates: [now]))
        XCTAssertNil(FitnessLogic.legWarning(gymDate: now, heavyLegs: true, badmintonDates: [now.addingTimeInterval(4 * 86400)]))
    }
    func testInventoryPrioritizesMatchingOption() {
        let options = FitnessLogic.mealOptions(remainingCalories: 1000, remainingProtein: 60, trained: false,
            badminton: false, inventory: ["chicken", "rice"], trend: FitnessLogic.weightTrend([]))
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options.first?.name, "Chicken rice bowl")
        XCTAssertTrue(options.first!.note.contains("inventory"))
    }
    func testActivityAndProteinNeedsAffectPortions() {
        let low = FitnessLogic.mealOptions(remainingCalories: 300, remainingProtein: 10, trained: false,
            badminton: false, inventory: [], trend: FitnessLogic.weightTrend([])).first { $0.name == "Chicken rice bowl" }!
        let high = FitnessLogic.mealOptions(remainingCalories: 1600, remainingProtein: 80, trained: true,
            badminton: false, inventory: [], trend: FitnessLogic.weightTrend([])).first { $0.name == "Chicken rice bowl" }!
        XCTAssertGreaterThan(high.calories, low.calories)
        XCTAssertGreaterThan(high.protein, low.protein)
        XCTAssertTrue(high.note.contains("activity"))
    }
    func testMockClearlyDisclosesNoRecognition() async throws {
        let estimate = try await MockFoodPhotoAnalyzer().analyze(imageData: Data([1]))
        XCTAssertTrue(estimate.explanation.contains("does not identify"))
        XCTAssertGreaterThan(estimate.calories, 0)
    }
    func testMockRejectsMissingImage() async {
        do {
            _ = try await MockFoodPhotoAnalyzer().analyze(imageData: Data())
            XCTFail("An empty image must not be analyzed")
        } catch { XCTAssertTrue(error is CocoaError) }
    }
}
