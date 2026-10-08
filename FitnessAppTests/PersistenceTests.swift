#if !SWIFT_PACKAGE
import XCTest
import SwiftData
@testable import LeanLog

@MainActor final class PersistenceTests: XCTestCase {
    private func makeStore(url: URL? = nil) throws -> (ModelContainer, AppStore) {
        let schema = Schema([UserProfile.self, DailyNutrition.self, Meal.self, FoodItem.self,
                             WeightEntry.self, WorkoutSession.self, ExerciseEntry.self, SleepEntry.self,
                             BadmintonEntry.self, FoodInventoryItem.self, WeeklySummary.self])
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true) }
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return (container, AppStore(context: container.mainContext))
    }
    func testBreakfastCountedOnlyOnceAndCanBeSkipped() throws {
        let (container, app) = try makeStore()
        XCTAssertEqual(app.calories, 0)
        app.skipBreakfast()
        XCTAssertEqual(app.calories, 0)
        app.restoreBreakfast()
        XCTAssertTrue(app.logOption(app.breakfast, breakfast: true))
        XCTAssertTrue(app.logOption(app.breakfast, breakfast: true))
        XCTAssertEqual(app.todayMeals.count, 1)
        XCTAssertEqual(app.calories, app.breakfast.calories, accuracy: 0.1)
        let reopened = AppStore(context: ModelContext(container))
        XCTAssertEqual(reopened.todayMeals.count, 1)
        XCTAssertEqual(reopened.day.breakfastStatus, "eaten")
        app.deleteMeal(app.todayMeals[0])
        XCTAssertEqual(app.day.breakfastStatus, "planned")
        XCTAssertEqual(app.calories, 0)
    }
    func testManualWeightWinsAndDailyUpsert() throws {
        let (_, app) = try makeStore()
        let date = Date()
        XCTAssertTrue(app.logWeight(kilograms: 63, date: date))
        app.importHealthWeights([HealthWeight(date: date, kilograms: 65)])
        XCTAssertEqual(app.weights.count, 1)
        XCTAssertEqual(app.weights.first?.kilograms, 63)
        XCTAssertTrue(app.logWeight(kilograms: 64, date: date))
        XCTAssertEqual(app.weights.count, 1)
        XCTAssertEqual(app.weights.first?.kilograms, 64)
    }
    func testMealSaveUpdatesRemainingAndSurvivesContextReload() throws {
        let (container, app) = try makeStore()
        XCTAssertTrue(app.logMeal(Meal(name: "Lunch", calories: 700, protein: 40)))
        XCTAssertEqual(app.remainingCalories, 2000)
        XCTAssertEqual(app.remainingProtein, 90)
        let reopened = AppStore(context: ModelContext(container))
        XCTAssertEqual(reopened.calories, 700)
        XCTAssertEqual(reopened.protein, 40)
    }
    func testBadmintonAndInventoryDeduplicate() throws {
        let (_, app) = try makeStore()
        XCTAssertTrue(app.logBadminton(date: .now))
        XCTAssertTrue(app.logBadminton(date: .now))
        app.addInventory(" Rice ")
        app.addInventory("rice")
        XCTAssertEqual(app.badminton.count, 1)
        XCTAssertEqual(app.inventory.count, 1)
    }
    func testMultipleExerciseRowsAreOneSessionForProgression() throws {
        let (_, app) = try makeStore()
        let workout = WorkoutSession()
        app.context.insert(workout)
        workout.exercises = [
            ExerciseEntry(name: "Squat", weightKG: 50, sets: 1, reps: 8, targetReps: 8, rpe: 7),
            ExerciseEntry(name: "Squat", weightKG: 40, sets: 1, reps: 8, targetReps: 8, rpe: 7),
            ExerciseEntry(name: "Squat", weightKG: 30, sets: 1, reps: 8, targetReps: 8, rpe: 7)
        ]
        XCTAssertTrue(app.save())
        XCTAssertTrue(app.exerciseAdvice(name: "Squat").contains(L10n.text("Target reps completed at manageable RPE. Consider adding 1–2.5 kg next session.")))
        XCTAssertFalse(app.exerciseAdvice(name: "Squat").contains(L10n.text("Recorded per-set performance dropped in two consecutive sessions. Check for planned lighter days; otherwise maintain or reduce load by 5–10% and review recovery.")))
    }
    func testBreakfastDisplaySnapshotAndMealChildrenSurviveReload() throws {
        let (container, app) = try makeStore()
        XCTAssertTrue(app.logOption(app.breakfast, breakfast: true))
        let calories = app.loggedBreakfast!.calories
        app.profile.breakfastOatsGrams = 100
        XCTAssertTrue(app.save())
        XCTAssertEqual(app.loggedBreakfast?.calories, calories)
        XCTAssertNotEqual(app.breakfast.calories, calories)
        app.skipBreakfast()
        XCTAssertEqual(app.day.breakfastStatus, "eaten")
        let reopened = AppStore(context: ModelContext(container))
        XCTAssertEqual(reopened.loggedBreakfast?.foods.count, 3)
        XCTAssertTrue(reopened.loggedBreakfast!.foods.allSatisfy { $0.meal?.id == reopened.loggedBreakfast?.id })
    }
    func testMealEditClearsStaleIngredientsAndDeletionCascades() throws {
        let (_, app) = try makeStore()
        XCTAssertTrue(app.logOption(app.breakfast, breakfast: true))
        let meal = try XCTUnwrap(app.loggedBreakfast)
        XCTAssertTrue(app.updateMeal(meal, name: "Edited breakfast", date: meal.date, calories: 550,
            protein: 30, carbs: 65, fat: 10, photoData: nil))
        XCTAssertEqual(app.calories, 550)
        XCTAssertTrue(try app.context.fetch(FetchDescriptor<FoodItem>()).isEmpty)
        app.deleteMeal(meal)
        XCTAssertEqual(app.day.breakfastStatus, "planned")
        XCTAssertTrue(app.logOption(app.breakfast, breakfast: true))
        app.deleteMeal(app.loggedBreakfast!)
        XCTAssertTrue(try app.context.fetch(FetchDescriptor<FoodItem>()).isEmpty)
    }
    func testReloadRollsDayWithoutDuplicatingBreakfastOrProfile() throws {
        let (container, _) = try makeStore()
        var now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let app = AppStore(context: ModelContext(container), now: { now })
        XCTAssertTrue(app.logOption(app.breakfast, breakfast: true))
        now = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        // Marking eaten without an explicit reload must roll to the new day itself.
        XCTAssertTrue(app.logOption(app.breakfast, breakfast: true))
        app.reload(); app.reload()
        XCTAssertEqual(app.meals.count, 2)
        XCTAssertEqual(app.todayMeals.count, 1)
        XCTAssertEqual(try app.context.fetch(FetchDescriptor<UserProfile>()).count, 1)
        XCTAssertEqual(try app.context.fetch(FetchDescriptor<DailyNutrition>()).count, 2)
    }
    func testHealthImportOrderIsIdempotentAndRejectsInvalidData() throws {
        let (_, app) = try makeStore()
        let day = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        let records = [HealthWeight(date: day.addingTimeInterval(100), kilograms: 64),
                       HealthWeight(date: day, kilograms: 63), HealthWeight(date: day, kilograms: .nan)]
        app.importHealthWeights(records); app.importHealthWeights(records)
        XCTAssertEqual(app.weights.count, 1)
        XCTAssertEqual(app.weights[0].kilograms, 64)
        app.importHealthSleep([HealthSleep(day: day, hours: 7), HealthSleep(day: day, hours: 8), HealthSleep(day: day, hours: .nan)])
        app.importHealthSleep([HealthSleep(day: day, hours: 8)])
        XCTAssertEqual(app.sleep.count, 1)
        XCTAssertEqual(app.sleep[0].hours, 8)
    }
    func testStoreRejectsInvalidOrFutureEntriesBeforeInsertion() throws {
        let (_, app) = try makeStore()
        XCTAssertFalse(app.logMeal(Meal(name: "Invalid", calories: .nan, protein: 10)))
        XCTAssertFalse(app.logMeal(Meal(date: Date().addingTimeInterval(86400), name: "Future", calories: 100, protein: 10)))
        XCTAssertFalse(app.logWeight(kilograms: -1, date: .now))
        XCTAssertTrue(app.meals.isEmpty)
        XCTAssertTrue(app.weights.isEmpty)
        XCTAssertFalse(app.context.hasChanges)
    }
    func testWorkoutEditReplacesChildrenAndHonoursTargetSets() throws {
        let (container, app) = try makeStore()
        let first = ExerciseEntry(name: "Squat", weightKG: 40, sets: 2, reps: 8, targetReps: 8, rpe: 7, targetSets: 3)
        XCTAssertTrue(app.saveWorkout(nil, name: "Legs", date: .now, exercises: [first]))
        XCTAssertTrue(app.exerciseAdvice(name: "squat").contains(L10n.text("Maintain workload until target reps feel controlled. Reduce load if form or recovery suffers.")))
        let workout = app.workouts[0]
        let replacement = ExerciseEntry(name: "Squat", weightKG: 40, sets: 3, reps: 8, targetReps: 8, rpe: 7, targetSets: 3)
        XCTAssertTrue(app.saveWorkout(workout, name: "Legs", date: workout.date, exercises: [replacement]))
        XCTAssertEqual(try app.context.fetch(FetchDescriptor<ExerciseEntry>()).count, 1)
        XCTAssertTrue(app.exerciseAdvice(name: "squat").contains(L10n.text("Target reps completed at manageable RPE. Consider adding 1–2.5 kg next session.")))
        let reopened = AppStore(context: ModelContext(container))
        XCTAssertEqual(reopened.workouts.first?.exercises.first?.targetSets, 3)
        XCTAssertEqual(reopened.workouts.first?.exercises.first?.session?.id, workout.id)
    }
    func testHealthActivityInfluencesCoachingWithoutInsertingManualSessions() throws {
        let (_, app) = try makeStore()
        app.healthWorkouts = [HealthWorkout(id: UUID(), date: .now, minutes: 30, label: "Strength", isGym: true),
                              HealthWorkout(id: UUID(), date: .now, minutes: 60, label: "Badminton", isBadminton: true)]
        XCTAssertTrue(app.trainedToday)
        XCTAssertTrue(app.badmintonToday)
        XCTAssertFalse(app.manuallyTrainedToday)
        XCTAssertTrue(app.workouts.isEmpty)
        XCTAssertTrue(app.badminton.isEmpty)
        XCTAssertTrue(app.recommendations.allSatisfy { $0.note.contains(L10n.text(" Include carbs to support today's activity.")) })
    }
    func testSummaryCoverageAndSavedSnapshotAreNotZeroFilledOrDuplicated() throws {
        let (_, app) = try makeStore()
        XCTAssertTrue(app.logMeal(Meal(name: "Lunch", calories: 700, protein: 40)))
        XCTAssertTrue(app.weeklySummaryText.contains("1/7"))
        XCTAssertTrue(app.weeklySummaryText.contains(L10n.text("%@ kcal", "700")))
        app.saveWeeklySummary(); app.saveWeeklySummary()
        XCTAssertEqual(app.summaries.count, 1)
    }
    func testRollbackRestoresProfileAndBreakfastReferences() throws {
        let (_, app) = try makeStore()
        app.profile.calorieTarget = 3000
        app.day.breakfastStatus = "eaten"
        app.context.rollback(); app.reload()
        XCTAssertTrue(app.isReady)
        XCTAssertEqual(app.profile.calorieTarget, 2700)
        XCTAssertEqual(app.day.breakfastStatus, "planned")
    }
    func testWorkoutRowOrderIsRetainedAcrossContextReload() throws {
        let (container, app) = try makeStore()
        XCTAssertTrue(app.saveWorkout(nil, name: "Gym", date: .now, exercises: [
            ExerciseEntry(name: "Warm-up squat", weightKG: 20, sets: 1, reps: 8, targetReps: 8, rpe: 5),
            ExerciseEntry(name: "Working squat", weightKG: 40, sets: 3, reps: 8, targetReps: 8, rpe: 7)
        ]))
        let reopened = AppStore(context: ModelContext(container))
        let rows = try XCTUnwrap(reopened.workouts.first).exercises.sorted { $0.position < $1.position }
        XCTAssertEqual(rows.map(\.name), ["Warm-up squat", "Working squat"])
        XCTAssertEqual(rows.map(\.position), [0, 1])
    }
    func testFileBackedStoreReopensWithLogsAndRelationships() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("logs.store")
        try autoreleasepool {
            let (_, app) = try makeStore(url: url)
            XCTAssertTrue(app.logOption(app.breakfast, breakfast: true))
            XCTAssertTrue(app.logWeight(kilograms: 63, date: .now))
            XCTAssertTrue(app.saveWorkout(nil, name: "Gym", date: .now, exercises: [
                ExerciseEntry(name: "Squat", weightKG: 40, sets: 3, reps: 8, targetReps: 8, rpe: 7, targetSets: 3)
            ]))
        }
        try autoreleasepool {
            let (_, reopened) = try makeStore(url: url)
            XCTAssertTrue(reopened.isReady)
            XCTAssertEqual(reopened.meals.count, 1)
            XCTAssertEqual(reopened.loggedBreakfast?.foods.count, 3)
            XCTAssertEqual(reopened.weights.first?.kilograms, 63)
            XCTAssertEqual(reopened.workouts.first?.exercises.first?.targetSets, 3)
            XCTAssertNotNil(reopened.workouts.first?.exercises.first?.session)
        }
    }
    func testWorkoutDeletionCascadesExercises() throws {
        let (_, app) = try makeStore()
        let workout = WorkoutSession()
        app.context.insert(workout)
        workout.exercises = [ExerciseEntry(name: "Squat", weightKG: 40, sets: 3, reps: 8, targetReps: 8, rpe: 7)]
        XCTAssertTrue(app.save())
        XCTAssertEqual(try app.context.fetch(FetchDescriptor<ExerciseEntry>()).count, 1)
        app.deleteWorkout(workout)
        XCTAssertTrue(try app.context.fetch(FetchDescriptor<ExerciseEntry>()).isEmpty)
    }
    func testAnalysedFoodEditsPersistAllFieldsWithoutDuplicateChildren() throws {
        let (container, app) = try makeStore()
        let meal = Meal(date: app.currentDate, name: "Rice", calories: 260, protein: 5.4, carbs: 56, fat: 0.6)
        meal.analysisSource = FoodAnalysisSource.mockFallback.rawValue
        meal.analysisConfidence = 0.2; meal.analysisNotes = "Demo fallback; correct manually."
        meal.foods = [FoodItem(name: "Cooked rice", grams: 200, calories: 260, protein: 5.4,
            carbs: 56, fat: 0.6, confidence: 0.2, uncertaintyNotes: "Cooked weight assumed.")]
        XCTAssertTrue(app.logMeal(meal))
        let edited = EstimatedFoodItem(name: "Cooked rice", grams: 150, calories: 195, protein: 4.05,
            carbs: 42, fat: 0.45, confidence: 0.8, uncertaintyNotes: "Portion weighed manually.")
        for _ in 0..<2 {
            XCTAssertTrue(app.updateMeal(meal, name: "Weighed lunch", date: meal.date, calories: 195,
                protein: 4.05, carbs: 42, fat: 0.45, photoData: nil, estimatedItems: [edited],
                source: .mockFallback, confidence: 0.8, notes: "Corrected after demo fallback."))
        }
        let reopened = AppStore(context: ModelContext(container))
        let saved = try XCTUnwrap(reopened.meals.first { $0.id == meal.id })
        XCTAssertEqual(saved.analysisSource, "mockFallback")
        XCTAssertEqual(saved.analysisConfidence, 0.8)
        XCTAssertEqual(saved.analysisNotes, "Corrected after demo fallback.")
        let food = try XCTUnwrap(saved.foods.first)
        XCTAssertEqual(food.name, edited.name); XCTAssertEqual(food.grams, 150)
        XCTAssertEqual(food.calories, 195); XCTAssertEqual(food.protein, 4.05)
        XCTAssertEqual(food.carbs, 42); XCTAssertEqual(food.fat, 0.45)
        XCTAssertEqual(food.confidence, 0.8); XCTAssertEqual(food.uncertaintyNotes, edited.uncertaintyNotes)
        XCTAssertEqual(food.meal?.id, saved.id)
        XCTAssertEqual(try reopened.context.fetch(FetchDescriptor<FoodItem>()).count, 1)
    }
    func testInvalidAnalysisDoesNotInsertOrReplaceSavedMeal() throws {
        let (_, app) = try makeStore()
        let invalid = Meal(date: app.currentDate, name: "Lunch", calories: 100, protein: 10)
        invalid.foods = [FoodItem(name: "Food", grams: -1, calories: 100, protein: 10, confidence: 0.5)]
        XCTAssertFalse(app.logMeal(invalid))
        XCTAssertTrue(try app.context.fetch(FetchDescriptor<Meal>()).isEmpty)
        let saved = Meal(date: app.currentDate, name: "Lunch", calories: 100, protein: 10)
        XCTAssertTrue(app.logMeal(saved))
        let food = EstimatedFoodItem(name: "Food", grams: 100, calories: 200, protein: 10,
            carbs: 0, fat: 0, confidence: 0.5, uncertaintyNotes: "")
        XCTAssertFalse(app.updateMeal(saved, name: "Changed", date: saved.date, calories: 100,
            protein: 10, carbs: 0, fat: 0, photoData: nil, estimatedItems: [food], source: .api))
        XCTAssertEqual(saved.name, "Lunch"); XCTAssertEqual(saved.calories, 100)
        XCTAssertTrue(saved.foods.isEmpty)
    }

}
#endif
