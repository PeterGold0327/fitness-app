import Foundation
import SwiftData
import Combine

@MainActor final class PersonalLibrary: ObservableObject {
    @Published private(set) var state = PersonalLibraryState()
    @Published var error: String?
    private var readFailed = false
    private let persistence: PersonalLibraryPersistence
    init(defaults: UserDefaults = .standard) {
        var preferences = defaults
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let name = "LeanLog.uiTests.personalLibrary"
            preferences = UserDefaults(suiteName: name)!
            preferences.removePersistentDomain(forName: name)
        }
        #endif
        persistence = PersonalLibraryPersistence(defaults: preferences)
        do { state = try persistence.load() }
        catch { readFailed = true; self.error = L10n.text("Saved templates could not load. The saved copy has not been overwritten.") }
    }
    @discardableResult func update(_ change: (inout PersonalLibraryState) -> Void) -> Bool {
        // A failed read must not silently overwrite a potentially recoverable saved copy.
        guard !readFailed else { return false }
        var draft = state; change(&draft)
        do { try persistence.save(draft); state = draft; error = nil; return true }
        catch { self.error = L10n.text("Templates could not save. Your previous templates remain intact."); return false }
    }
    func plan(_ split: TrainingSplit?, date: Date) { update { $0.plannedSplit = split; $0.plannedDate = date } }
    func planned(on date: Date) -> TrainingSplit? {
        guard let day = state.plannedDate, Calendar.current.isDate(day, inSameDayAs: date) else { return nil }
        return state.plannedSplit
    }
}

extension AppStore {
    func coachInput(activeCalories: Double? = nil, usualActiveCalories: Double? = nil) -> DailyCoachInput {
        let planned = library.planned(on: currentDate)
        let historyAvailable = library.state.workouts.first { $0.id == planned }?.exercises.contains { !exerciseHistory($0.name).isEmpty } ?? false
        return DailyCoachInput(nutrition: todayMeals.isEmpty ? nil : CoachNutrition(calories: calories, protein: protein),
            calorieTarget: profile.calorieTarget, proteinTarget: profile.proteinTarget,
            plannedTraining: planned?.title, trained: trainedToday, hasTrainingHistory: historyAvailable,
            badminton: badmintonToday, sleepHours: latestSleep?.hours,
            activeCalories: activeCalories, usualActiveCalories: usualActiveCalories, trend: trend)
    }
    func exerciseHistory(_ name: String, before date: Date? = nil, excluding id: UUID? = nil) -> [ExerciseSessionSnapshot] {
        let canonical = TrainingCoach.canonical(name)
        let history = workouts.compactMap { session -> ExerciseSessionSnapshot? in
            let rows = session.exercises.sorted { $0.position < $1.position }.filter { TrainingCoach.canonical($0.name) == canonical }
            let sets = rows.flatMap { row in
                (0..<max(0, min(30, row.sets))).map { _ in TrainingSet(weightKG: row.weightKG, reps: row.reps, rpe: row.rpe) }
            }
            return sets.isEmpty ? nil : ExerciseSessionSnapshot(id: session.id, date: session.date, sets: sets)
        }
        return TrainingCoach.previous(history, before: date ?? currentDate, excluding: id)
    }
    @discardableResult func saveMealTemplate(_ meal: Meal) -> Bool {
        let items = meal.foods.sorted { $0.position < $1.position }.map {
            EstimatedFoodItem(name: $0.name, grams: $0.grams, calories: $0.calories, protein: $0.protein,
                              carbs: $0.carbs, fat: $0.fat, confidence: $0.confidence ?? 0, uncertaintyNotes: $0.uncertaintyNotes)
        }
        var template = SavedMealTemplate(name: meal.name, calories: meal.calories, protein: meal.protein, carbs: meal.carbs, fat: meal.fat, items: items)
        // Old aggregate meals may not have complete component nutrition.
        if !template.valid { template.items = [] }
        return library.update { state in
            if let index = state.meals.firstIndex(where: { $0.name.caseInsensitiveCompare(meal.name) == .orderedSame }) {
                template.id = state.meals[index].id; state.meals[index] = template
            } else { state.meals.append(template) }
        }
    }
    @discardableResult func logMealTemplate(_ template: SavedMealTemplate) -> Bool {
        guard template.valid else { return false }
        let meal = Meal(date: currentDate, name: template.name, calories: template.calories, protein: template.protein, carbs: template.carbs, fat: template.fat)
        meal.analysisSource = FoodAnalysisSource.recipe.rawValue
        meal.foods = template.items.enumerated().map { position, item in
            let food = FoodItem(name: item.name, grams: item.grams, calories: item.calories, protein: item.protein,
                                carbs: item.carbs, fat: item.fat, confidence: item.confidence, uncertaintyNotes: item.uncertaintyNotes)
            food.position = position; return food
        }
        return logMeal(meal)
    }
    var yesterdayMeals: [Meal] {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: currentDate)!
        return meals.filter { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
    }
    var yesterdayNutritionSummary: String {
        guard !yesterdayMeals.isEmpty else { return L10n.text("No meals recorded yesterday. There is not enough information to judge nutrition.") }
        let energy = yesterdayMeals.reduce(0) { $0 + $1.calories }
        let protein = yesterdayMeals.reduce(0) { $0 + $1.protein }
        return L10n.text("Recorded protein: %@. Calories differ from your current target by %@ kcal.",
                         protein >= profile.proteinTarget ? L10n.text("Target met") : L10n.text("Below target"),
                         String(Int((energy - profile.calorieTarget).rounded())))
    }
}
