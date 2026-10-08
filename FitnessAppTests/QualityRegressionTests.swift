import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import FitnessCore
#else
@testable import LeanLog
#endif

final class QualityRegressionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 14))! }
    private func trendPoints(gain: Double) -> [WeightPoint] {
        (0..<14).map { index in
            WeightPoint(date: calendar.date(byAdding: .day, value: -index, to: now)!, kilograms: 63 - Double(index) * gain / 7)
        }
    }
    func testTrendBoundariesAreOnTargetDespiteFloatingPointNoise() {
        for gain in [0.1, 0.25] {
            let trend = FitnessLogic.weightTrend(trendPoints(gain: gain), now: now, calendar: calendar)
            XCTAssertEqual(trend.label, "On target")
            XCTAssertNil(trend.calorieAdjustment)
        }
    }
    func testNonFiniteWeightsAndFutureSameDaySamplesAreIgnored() {
        let points = [WeightPoint(date: now, kilograms: 63), WeightPoint(date: now, kilograms: .infinity),
                      WeightPoint(date: now, kilograms: .nan), WeightPoint(date: now.addingTimeInterval(60), kilograms: 100)]
        XCTAssertEqual(FitnessLogic.weightTrend(points, now: now, calendar: calendar).average, 63)
    }
    func testInvalidComparisonWindowDoesNotCrashOrAdjustTargets() {
        for weeks in [0, -1, Int.max] {
            XCTAssertNil(FitnessLogic.weightTrend([], now: now, weeks: weeks).calorieAdjustment)
        }
    }
    func testDailyWindowsSurviveDaylightSavingChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9))!
        let points = (0..<14).map { index in
            WeightPoint(date: calendar.date(byAdding: .day, value: -index, to: end)!, kilograms: 63)
        }
        XCTAssertEqual(FitnessLogic.weightTrend(points, now: end, calendar: calendar).weeklyGain, 0)
    }
    func testIncompleteTargetSetsNeverSuggestIncrease() {
        let incomplete = ExercisePerformance(date: now, weight: 40, sets: 2, reps: 8, targetReps: 8, rpe: 7, targetSets: 3)
        XCTAssertTrue(FitnessLogic.progression([incomplete]).contains("Maintain"))
    }
    func testFewerPlannedSetsAreNotTwoPerformanceDrops() {
        let entries = (0..<3).map { index in
            ExercisePerformance(date: now.addingTimeInterval(Double(index) * 86400), weight: 40,
                                sets: 3 - index, reps: 8, targetReps: 8, rpe: 7, targetSets: 3 - index)
        }
        XCTAssertFalse(FitnessLogic.progression(entries).contains("two consecutive"))
    }
    func testZeroCompletedSetsAndRepsDoNotSuggestIncrease() {
        let failed = ExercisePerformance(date: now, weight: 40, sets: 0, reps: 0, targetReps: 8, rpe: 10, targetSets: 3)
        XCTAssertTrue(FitnessLogic.progression([failed]).contains("Maintain"))
    }
    func testInvalidPerformanceDoesNotBecomeARecommendation() {
        let invalid = ExercisePerformance(date: now, weight: .nan, sets: 3, reps: 8, targetReps: 8, rpe: 7)
        XCTAssertTrue(FitnessLogic.progression([invalid]).contains("baseline"))
    }
    func testBodyweightExerciseSuggestsRepsInsteadOfKilograms() {
        let entry = ExercisePerformance(date: now, weight: 0, sets: 3, reps: 8, targetReps: 8, rpe: 7, targetSets: 3)
        XCTAssertTrue(FitnessLogic.progression([entry]).contains("one more rep"))
    }
    func testNumericInputRejectsPartialOrUnusableValues() {
        for text in ["", " ", "12abc", "1e300", "NaN", "inf", "1.2.3", "1,000"] {
            XCTAssertNil(NumericInput.parse(text, locale: Locale(identifier: "en_AU")))
        }
        XCTAssertEqual(NumericInput.parse("63.5", locale: Locale(identifier: "en_AU")), 63.5)
        XCTAssertEqual(NumericInput.parse("63,5", locale: Locale(identifier: "fr_FR")), 63.5)
        XCTAssertEqual(NumericInput.parse("0", locale: Locale(identifier: "en_AU")), 0)
    }
    func testValidatorsAllowZeroCalorieDrinkButRejectNegativeAndOverflowValues() {
        XCTAssertTrue(EntryValidation.meal(name: "Water", calories: 0, protein: 0, carbs: 0, fat: 0))
        XCTAssertFalse(EntryValidation.meal(name: " ", calories: 10, protein: 0, carbs: 0, fat: 0))
        XCTAssertFalse(EntryValidation.meal(name: "Food", calories: .infinity, protein: 0, carbs: 0, fat: 0))
        XCTAssertFalse(EntryValidation.meal(name: "Food", calories: 20001, protein: 0, carbs: 0, fat: 0))
        XCTAssertFalse(EntryValidation.meal(name: "Food", calories: 100, protein: -1, carbs: 0, fat: 0))
        XCTAssertFalse(EntryValidation.weight(.nan))
        XCTAssertFalse(EntryValidation.profile(height: 178, startingWeight: 63, calories: 1000, protein: 300,
            fat: 70, yogurt: 200, banana: 120, oats: 60))
    }
    func testInventoryMatchesWordsAndAustralianSpelling() {
        XCTAssertTrue(FitnessLogic.inventoryMatches("bananas", ingredient: "banana"))
        XCTAssertTrue(FitnessLogic.inventoryMatches("yoghurt", ingredient: "Greek yogurt"))
        XCTAssertTrue(FitnessLogic.inventoryMatches("chicken", ingredient: "chicken breast (cooked)"))
        XCTAssertFalse(FitnessLogic.inventoryMatches("ice", ingredient: "rice (cooked)"))
        XCTAssertFalse(FitnessLogic.inventoryMatches("", ingredient: "rice"))
    }
    func testRecipesWarnWhenNormalPortionExceedsRemainingCalories() {
        let options = FitnessLogic.mealOptions(remainingCalories: 50, remainingProtein: 20, trained: false,
            badminton: false, inventory: [], trend: FitnessLogic.weightTrend([]))
        XCTAssertEqual(options.count, 3)
        XCTAssertTrue(options.allSatisfy { $0.note.contains("exceeds") })
    }
    func testSleepAttributedToWakingDayAndClippedAtRefreshTime() {
        let midnight = calendar.startOfDay(for: now)
        let night = DateInterval(start: midnight.addingTimeInterval(-2 * 3600), duration: 10 * 3600)
        let duplicate = DateInterval(start: midnight, duration: 6 * 3600)
        let morning = midnight.addingTimeInterval(7 * 3600)
        let nights = FitnessLogic.sleepNights([night, duplicate], now: morning, days: 2, calendar: calendar)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].day, midnight)
        XCTAssertEqual(nights[0].hours, 9, accuracy: 0.001)
    }
    func testSleepWindowsSplitAtNoonWithoutCountingMissingNightsAsZero() {
        let midnight = calendar.startOfDay(for: now)
        let interval = DateInterval(start: midnight.addingTimeInterval(11 * 3600), duration: 2 * 3600)
        let tomorrow = midnight.addingTimeInterval(24 * 3600 + 14 * 3600)
        let nights = FitnessLogic.sleepNights([interval], now: tomorrow, days: 3, calendar: calendar)
        XCTAssertEqual(nights.count, 2)
        XCTAssertEqual(nights.reduce(0) { $0 + $1.hours }, 2)
        XCTAssertTrue(FitnessLogic.sleepNights([], now: now).isEmpty)
    }
    func testSafeNumberDisplayDoesNotTrapOnInvalidData() {
        XCTAssertEqual(Double.infinity.wholeText, "—")
        XCTAssertEqual(Double.nan.wholeText, "—")
        XCTAssertFalse(Double.greatestFiniteMagnitude.wholeText.isEmpty)
    }
}
