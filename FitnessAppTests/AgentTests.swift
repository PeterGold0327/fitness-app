import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import FitnessCore
#else
@testable import LeanLog
#endif

final class AgentTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1791504000)
    func input() -> DailyCoachInput { DailyCoachInput(nutrition: CoachNutrition(calories: 1600, protein: 80), calorieTarget: 2700, proteinTarget: 130) }
    func session(_ days: Int, _ reps: [Int], weight: Double = 60, rpe: Double = 8) -> ExerciseSessionSnapshot {
        ExerciseSessionSnapshot(id: UUID(), date: now.addingTimeInterval(-Double(days) * 86400), sets: reps.map { TrainingSet(weightKG: weight, reps: $0, rpe: rpe) })
    }
    func testHomeShowsAtMostTwoActionsAndPrioritizesSelectedTraining() {
        var data = input(); data.plannedTraining = "Chest"; data.activeCalories = 1100; data.sleepHours = 5
        let actions = DailyCoach.actions(data)
        XCTAssertEqual(actions.map(\.kind), [.training, .nutrition])
        XCTAssertTrue(actions[0].text.contains(L10n.text("Chest")))
        XCTAssertTrue(actions[0].text.contains("Sleep"))
    }
    func testMissingNutritionAndSleepAreNotInvented() {
        var data = input(); data.nutrition = nil; data.sleepHours = nil
        let actions = DailyCoach.actions(data)
        XCTAssertEqual(actions.first?.kind, .logMeal)
        XCTAssertFalse(actions.contains { $0.kind == .recovery || $0.kind == .activity })
        data.plannedTraining = "Chest"
        XCTAssertEqual(DailyCoach.actions(data).first?.text, L10n.text("Today: %@. Choose a comfortable first load and record your actual reps.", L10n.text("Chest")))
        XCTAssertFalse(DailyCoach.highActivity(data))
    }
    func testNearCalorieTargetDoesNotReimburseExerciseEnergy() {
        var data = input(); data.nutrition = CoachNutrition(calories: 2650, protein: 130); data.activeCalories = 1200
        XCTAssertEqual(DailyCoach.actions(data).first?.text, L10n.text("Activity is high, but logged calories are near your target. Do not automatically eat back all exercise calories."))
        XCTAssertEqual(data.calorieTarget, 2700)
    }
    func testActivityBaselineRequiresRealValuesAndMissingDoesNotMeanZero() {
        var data = input(); data.activeCalories = 750; data.usualActiveCalories = nil
        XCTAssertFalse(DailyCoach.highActivity(data))
        data.usualActiveCalories = 300; XCTAssertTrue(DailyCoach.highActivity(data))
        data.activeCalories = .nan; XCTAssertFalse(DailyCoach.highActivity(data))
    }
    func testWeightAdviceRequiresAdequateComparisonData() {
        var data = input(); data.nutrition = CoachNutrition(calories: 2700, protein: 130)
        data.trend = FitnessLogic.weightTrend([], now: now)
        XCTAssertFalse(DailyCoach.actions(data).contains { $0.kind == .weight })
        data.trend = WeightTrend(average: 65, weeklyGain: 0.2, label: "On target", advice: "Maintain", calorieAdjustment: nil)
        XCTAssertEqual(DailyCoach.actions(data).first?.kind, .weight)
    }
    func testActivityMealAddsOnlyModestCarbsWhenThereIsRoom() throws {
        var data = input(); data.nutrition = CoachNutrition(calories: 600, protein: 40); data.activeCalories = 1200
        let option = MealOption(name: "Rice", ingredients: [Ingredient(name: "rice (cooked)", grams: 200, caloriesPer100: 130, proteinPer100: 2.7, carbsPer100: 28, fatPer100: 0.3)], note: "")
        let result = try XCTUnwrap(DailyCoach.meal([option], input: data))
        XCTAssertEqual(result.ingredients[0].grams, 250)
        XCTAssertEqual(result.calories - option.calories, 65)
        data.nutrition = CoachNutrition(calories: 2690, protein: 130)
        XCTAssertEqual(DailyCoach.meal([option], input: data)?.calories, option.calories)
        XCTAssertNil(DailyCoach.meal([], input: data))
    }
    func testEquivalentExerciseNamesShareHistoryWithoutMergingDifferentMovements() {
        for name in [" Bench Press ", "Barbell Bench Press", "杠铃卧推", "平板卧推", "卧推"] { XCTAssertEqual(TrainingCoach.canonical(name), "bench press") }
        XCTAssertNotEqual(TrainingCoach.canonical("Incline Dumbbell Press"), TrainingCoach.canonical("卧推"))
        XCTAssertNotEqual(TrainingCoach.canonical("Machine Chest Press"), TrainingCoach.canonical("卧推"))
        XCTAssertNotEqual(TrainingCoach.canonical("Pull-up"), TrainingCoach.canonical("Lat Pulldown"))
    }
    func testPreviousSessionExcludesFutureCurrentAndIncompleteWorkouts() {
        let old = session(3, [10, 9, 8]); let current = session(0, [10]); let invalid = session(1, [0])
        let future = session(-2, [10])
        XCTAssertEqual(TrainingCoach.previous([old, current, invalid, future], before: now).map(\.id), [old.id])
        XCTAssertTrue(TrainingCoach.previous([old], before: now, excluding: old.id).isEmpty)
    }
    func testDoubleProgressionUsesActualPerSetReps() {
        let advice = TrainingCoach.advice([session(3, [10, 9, 8])], now: now)
        XCTAssertEqual(advice, L10n.text("Keep the previous load; aim for %@ reps if comfortable.", "10 / 10 / 9"))
        XCTAssertEqual(TrainingCoach.advice([session(3, [10, 10, 10], rpe: 7)], now: now), L10n.text("All previous sets felt comfortable. Consider a small load increase next time."))
        XCTAssertNotEqual(TrainingCoach.advice([session(3, [10, 10, 10], rpe: 9)], now: now), L10n.text("All previous sets felt comfortable. Consider a small load increase next time."))
    }
    func testRepeatedDropGapAndShortSleepKeepLoadConservative() {
        let history = [session(1, [8, 8]), session(5, [9, 9]), session(9, [10, 10])]
        XCTAssertEqual(TrainingCoach.advice(history, now: now), L10n.text("Reps fell in the last two sessions at the same load. Keep the weight steady this time."))
        XCTAssertEqual(TrainingCoach.advice([session(30, [10, 10])], now: now), L10n.text("Returning after a gap: start at or below the previous load and keep the first session comfortable."))
        XCTAssertEqual(TrainingCoach.advice(history, now: now, sleepHours: 5), L10n.text("Sleep was short; keep the previous load and stop before straining."))
    }
    func testCompletedWorkoutComparesRepsOnlyAtMatchingLoadsAndSetCount() {
        let previous = session(4, [10, 9, 8]).sets
        XCTAssertEqual(TrainingCoach.comparison(today: session(0, [10, 10, 9]).sets, previous: previous), L10n.text("At the same load: %@ total reps compared with last time.", "+2"))
        XCTAssertEqual(TrainingCoach.comparison(today: session(0, [10, 9, 8], weight: 65).sets, previous: previous), L10n.text("Loads or set count changed. Use this session as the next comparison."))
    }
    func testFourTemplatesHaveNoMoreThanOneOptionalAccessoryAndCanBeEdited() {
        let defaults = WorkoutTemplate.defaults
        XCTAssertEqual(Set(defaults.map(\.id)), Set(TrainingSplit.allCases))
        XCTAssertTrue(defaults.allSatisfy(\.valid))
        XCTAssertTrue(defaults.allSatisfy { $0.exercises.filter(\.accessory).count == 1 })
        var edited = defaults[0]; edited.exercises[0].name = "杠铃卧推"
        XCTAssertTrue(edited.valid)
        edited.exercises[0].accessory = true; XCTAssertFalse(edited.valid)
    }
    func testTemplatePlanAndMealPreferencesSurviveReload() throws {
        let suite = "LeanLog.tests.\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = PersonalLibraryPersistence(defaults: defaults)
        var state = try storage.load()
        state.workouts[0].exercises[0].name = "平板卧推"
        state.plannedSplit = .back; state.plannedDate = now
        state.meals = [SavedMealTemplate(name: "牛肉饭", calories: 650, protein: 45, carbs: 70, fat: 20)]
        state.manualActivities = [ManualActivityRecord(date: now, badminton: true, minutes: 96, activeCalories: 742)]
        state.goalWeightKG = 68
        try storage.save(state)
        let reopened = try storage.load()
        XCTAssertEqual(reopened.workouts[0].exercises[0].name, "平板卧推")
        XCTAssertEqual(reopened.plannedSplit, .back)
        XCTAssertEqual(reopened.meals.first?.calories, 650)
        XCTAssertEqual(reopened.manualActivities.first?.minutes, 96)
        XCTAssertEqual(reopened.goalWeightKG, 68)
    }
    func testInvalidSaveAndCorruptLoadNeverReplaceSavedPreferenceCopy() throws {
        let suite = "LeanLog.tests.\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = PersonalLibraryPersistence(defaults: defaults)
        let state = PersonalLibraryState(); try storage.save(state)
        let original = defaults.data(forKey: PersonalLibraryPersistence.key)
        var invalid = state; invalid.workouts.removeLast()
        XCTAssertThrowsError(try storage.save(invalid))
        XCTAssertEqual(defaults.data(forKey: PersonalLibraryPersistence.key), original)
        let corrupt = Data("do not overwrite".utf8); defaults.set(corrupt, forKey: PersonalLibraryPersistence.key)
        XCTAssertThrowsError(try storage.load())
        XCTAssertEqual(defaults.data(forKey: PersonalLibraryPersistence.key), corrupt)
    }
    func testMealTemplateRejectsMismatchedComponentTotals() {
        let item = EstimatedFoodItem(name: "豆腐", grams: 100, calories: 80, protein: 8, carbs: 2, fat: 4, confidence: 0, uncertaintyNotes: "")
        var meal = SavedMealTemplate(name: "豆腐", calories: 80, protein: 8, carbs: 2, fat: 4, items: [item])
        XCTAssertTrue(meal.valid)
        meal.calories = 180; XCTAssertFalse(meal.valid)
    }
    func testManualActivityNeverInventsEnergyAndRejectsInvalidDuration() {
        var activity = ManualActivityRecord(date: now, badminton: true, minutes: 96)
        XCTAssertNil(activity.activeCalories); XCTAssertTrue(activity.valid)
        activity.minutes = 0; XCTAssertFalse(activity.valid)
        activity.minutes = 96; activity.activeCalories = -1; XCTAssertFalse(activity.valid)
    }
}
