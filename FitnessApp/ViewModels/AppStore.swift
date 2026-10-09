import Foundation
import SwiftData
import Combine

@MainActor final class AppStore: ObservableObject {
    let library: PersonalLibrary
    let context: ModelContext
    private let clock: () -> Date
    var currentDate: Date { clock() }
    @Published private(set) var isReady = false
    @Published var healthWorkouts: [HealthWorkout] = []
    @Published var profile: UserProfile
    @Published var meals: [Meal] = []
    @Published var weights: [WeightEntry] = []
    @Published var workouts: [WorkoutSession] = []
    @Published var sleep: [SleepEntry] = []
    @Published var badminton: [BadmintonEntry] = []
    @Published var inventory: [FoodInventoryItem] = []
    @Published var summaries: [WeeklySummary] = []
    @Published var milestones: [GrowthMilestone] = []
    @Published var progressPhotos: [ProgressPhoto] = []
    @Published var day: DailyNutrition
    @Published var errorMessage: String?
    let foodAnalysisSettings: FoodAnalysisSettings

    init(context: ModelContext, now: @escaping () -> Date = Date.init, foodAnalysisSettings: FoodAnalysisSettings? = nil, library: PersonalLibrary? = nil) {
        self.library = library ?? PersonalLibrary()
        self.context = context
        self.foodAnalysisSettings = foodAnalysisSettings ?? FoodAnalysisSettings()
        self.clock = now
        self.profile = UserProfile()
        self.day = DailyNutrition(day: now())
        // UI forms stage edits locally; only explicit, validated saves should persist.
        context.autosaveEnabled = false
        reload()
    }

    func reload() {
        do {
            let profiles = try context.fetch(FetchDescriptor<UserProfile>())
            if let existing = profiles.first { profile = existing }
            else { profile = UserProfile(); profile.name = L10n.text("Me"); context.insert(profile) }
            meals = try context.fetch(FetchDescriptor<Meal>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            weights = try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.day)]))
            workouts = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            sleep = try context.fetch(FetchDescriptor<SleepEntry>(sortBy: [SortDescriptor(\.day, order: .reverse)]))
            badminton = try context.fetch(FetchDescriptor<BadmintonEntry>(sortBy: [SortDescriptor(\.day, order: .reverse)]))
            inventory = try context.fetch(FetchDescriptor<FoodInventoryItem>(sortBy: [SortDescriptor(\.name)]))
            summaries = try context.fetch(FetchDescriptor<WeeklySummary>(sortBy: [SortDescriptor(\.weekStart, order: .reverse)]))
            milestones = try context.fetch(FetchDescriptor<GrowthMilestone>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            progressPhotos = try context.fetch(FetchDescriptor<ProgressPhoto>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            reconcileTimelineMilestones()
            let today = Calendar.current.startOfDay(for: currentDate)
            let days = try context.fetch(FetchDescriptor<DailyNutrition>())
            if let existing = days.first(where: { Calendar.current.isDate($0.day, inSameDayAs: today) }) { day = existing }
            else { day = DailyNutrition(day: today); context.insert(day) }
            // Reconcile persisted state with the actual breakfast, including after rollback/deletion.
            if todayMeals.contains(where: \.isBreakfast) { day.breakfastStatus = "eaten" }
            else if day.breakfastStatus != "skipped" { day.breakfastStatus = "planned" }
            if context.hasChanges { try context.save() }
            isReady = true
            errorMessage = nil
        } catch {
            context.rollback()
            isReady = false
            errorMessage = L10n.text("Could not load local data: %@. Your logs have not been deleted.", String(describing: error.localizedDescription))
        }
    }

    @discardableResult func save() -> Bool {
        do { try context.save(); reload(); objectWillChange.send(); return true }
        catch {
            context.rollback()
            reload()
            errorMessage = L10n.text("Could not save changes: %@. Please try again.", String(describing: error.localizedDescription))
            return false
        }
    }

    var todayMeals: [Meal] { meals.filter { Calendar.current.isDate($0.date, inSameDayAs: currentDate) } }
    var calories: Double { todayMeals.reduce(0) { $0 + $1.calories } }
    var protein: Double { todayMeals.reduce(0) { $0 + $1.protein } }
    var remainingCalories: Double { max(0, profile.calorieTarget - calories) }
    var remainingProtein: Double { max(0, profile.proteinTarget - protein) }
    var manuallyTrainedToday: Bool { workouts.contains { Calendar.current.isDate($0.date, inSameDayAs: currentDate) } }
    var manuallyPlayedBadmintonToday: Bool { badminton.contains { Calendar.current.isDate($0.day, inSameDayAs: currentDate) } }
    var trainedToday: Bool { manuallyTrainedToday || healthWorkouts.contains { $0.isGym && Calendar.current.isDate($0.date, inSameDayAs: currentDate) } }
    var badmintonToday: Bool { manuallyPlayedBadmintonToday || healthWorkouts.contains { $0.isBadminton && Calendar.current.isDate($0.date, inSameDayAs: currentDate) } }
    var badmintonDates: [Date] { badminton.map(\.day) + healthWorkouts.filter(\.isBadminton).map(\.date) }
    var loggedBreakfast: Meal? { todayMeals.first(where: \.isBreakfast) }
    var weightPoints: [WeightPoint] { weights.filter { EntryValidation.weight($0.kilograms) }.map { WeightPoint(date: $0.day, kilograms: $0.kilograms) } }
    var trend: WeightTrend { FitnessLogic.weightTrend(weightPoints, now: currentDate) }
    var breakfast: MealOption {
        FitnessLogic.breakfast(yogurt: profile.breakfastYogurtGrams, banana: profile.breakfastBananaGrams, oats: profile.breakfastOatsGrams)
    }
    var recommendations: [MealOption] {
        FitnessLogic.mealOptions(remainingCalories: remainingCalories, remainingProtein: remainingProtein,
                                trained: trainedToday, badminton: badmintonToday,
                                inventory: inventory.map(\.name), trend: trend)
    }
    var latestSleep: SleepEntry? { sleep.first { Calendar.current.isDate($0.day, inSameDayAs: currentDate) } }
    var recentSleepAverage: Double? {
        FitnessLogic.average(sleep.filter { $0.day >= startOfRecentDays(7) && $0.day <= currentDate }.map(\.hours))
    }
    func startOfRecentDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: currentDate))!
    }
    func weightText(_ kg: Double) -> String {
        String(format: "%.1f %@", locale: Locale.current, profile.usesPounds ? kg * 2.2046226218 : kg, profile.usesPounds ? L10n.text("lb") : L10n.text("kg"))
    }
    func kilograms(from displayed: Double) -> Double { profile.usesPounds ? displayed / 2.2046226218 : displayed }
    func displayedWeight(_ kg: Double) -> Double { profile.usesPounds ? kg * 2.2046226218 : kg }

    private func reject(_ message: String) -> Bool { errorMessage = message; return false }
    @discardableResult func logMeal(_ meal: Meal) -> Bool {
        guard isReady, meal.date <= currentDate,
              EntryValidation.meal(name: meal.name, calories: meal.calories, protein: meal.protein, carbs: meal.carbs, fat: meal.fat) else {
            return reject(L10n.text("Enter a meal name, valid nonnegative nutrition values and a date that is not in the future."))
        }
        guard meal.mealCategory.isEmpty || TimelineMealCategory(rawValue: meal.mealCategory) != nil else {
            return reject(L10n.text("Choose a valid meal category."))
        }
        guard meal.analysisNotes.count <= 4000,
              meal.analysisConfidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              FoodAnalysisSource(rawValue: meal.analysisSource) != nil else { return reject(L10n.text("Check analysis confidence and notes.")) }
        if meal.foods.contains(where: { $0.confidence != nil }) {
            guard meal.foods.allSatisfy({ $0.confidence != nil }) else { return reject(L10n.text("Check all detected food items.")) }
            let items = meal.foods.map {
                EstimatedFoodItem(name: $0.name, grams: $0.grams, calories: $0.calories, protein: $0.protein,
                    carbs: $0.carbs, fat: $0.fat, confidence: $0.confidence ?? 0, uncertaintyNotes: $0.uncertaintyNotes)
            }
            let estimate = FoodEstimate(name: meal.name, items: items, confidence: meal.analysisConfidence ?? 0,
                uncertaintyNotes: meal.analysisNotes, source: FoodAnalysisSource(rawValue: meal.analysisSource) ?? .manual)
            guard estimate.valid, abs(estimate.calories - meal.calories) < 0.001,
                  abs(estimate.protein - meal.protein) < 0.001, abs(estimate.carbs - meal.carbs) < 0.001,
                  abs(estimate.fat - meal.fat) < 0.001 else { return reject(L10n.text("Check detected foods and their combined meal totals.")) }
        }
        context.insert(meal); return save()
    }

    @discardableResult func updateMeal(_ meal: Meal, name: String, date: Date, calories: Double,
                                       protein: Double, carbs: Double, fat: Double, photoData: Data?, estimatedItems: [EstimatedFoodItem] = [],
                                       source: FoodAnalysisSource = .manual, confidence: Double? = nil, notes: String = "", category: String? = nil) -> Bool {
        guard isReady, date <= currentDate,
              EntryValidation.meal(name: name, calories: calories, protein: protein, carbs: carbs, fat: fat),
              !meal.isBreakfast || Calendar.current.isDate(date, inSameDayAs: meal.date) else {
            return reject(L10n.text("Check the meal name, date and nutrition values before saving."))
        }
        if !estimatedItems.isEmpty {
            let estimate = FoodEstimate(name: name, items: estimatedItems, confidence: confidence ?? 0, uncertaintyNotes: notes, source: source)
            guard estimate.valid, abs(estimate.calories - calories) < 0.001, abs(estimate.protein - protein) < 0.001,
                  abs(estimate.carbs - carbs) < 0.001, abs(estimate.fat - fat) < 0.001 else {
                return reject(L10n.text("Check each detected food's grams, macros, confidence and notes. Meal totals must equal the food items."))
            }
        }
        guard notes.count <= 4000, confidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true else { return reject(L10n.text("Check analysis confidence and notes.")) }
        guard category.map({ $0.isEmpty || TimelineMealCategory(rawValue: $0) != nil }) ?? true else {
            return reject(L10n.text("Choose a valid meal category."))
        }
        let oldFoods = meal.foods
        meal.foods = []
        for food in oldFoods { context.delete(food) }
        if let category {
            meal.mealCategory = category
        }
        meal.name = name; meal.date = date; meal.calories = calories; meal.protein = protein
        meal.carbs = carbs; meal.fat = fat; meal.photoData = photoData
        meal.analysisSource = source.rawValue; meal.analysisConfidence = confidence; meal.analysisNotes = notes
        for (position, item) in estimatedItems.enumerated() {
            let food = FoodItem(name: item.name, grams: item.grams, calories: item.calories, protein: item.protein,
                carbs: item.carbs, fat: item.fat, confidence: item.confidence, uncertaintyNotes: item.uncertaintyNotes)
            context.insert(food); food.position = position; meal.foods.append(food)
        }
        return save()
    }

    @discardableResult func saveWorkout(_ existing: WorkoutSession?, name: String, date: Date, exercises: [ExerciseEntry]) -> Bool {
        guard isReady, date <= currentDate, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !exercises.isEmpty, exercises.allSatisfy({
                  !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.weightKG <= 1000 &&
                  ExercisePerformance(date: date, weight: $0.weightKG, sets: $0.sets, reps: $0.reps,
                      targetReps: $0.targetReps, rpe: $0.rpe, targetSets: $0.targetSets).valid
              }) else { return reject(L10n.text("Check exercise names, loads, completed/target sets and reps, and RPE before saving.")) }
        let session = existing ?? WorkoutSession(date: date, name: name)
        if existing == nil { context.insert(session) }
        let oldExercises = session.exercises
        session.exercises = []
        for exercise in oldExercises { context.delete(exercise) }
        session.name = name.trimmingCharacters(in: .whitespacesAndNewlines); session.date = date
        for (position, exercise) in exercises.enumerated() {
            context.insert(exercise)
            exercise.position = position
        }
        session.exercises = exercises
        let success = save()
        if success, library.state.manualActivities.contains(where: { $0.workoutID == session.id }) {
            library.update { state in
                for index in state.manualActivities.indices where state.manualActivities[index].workoutID == session.id {
                    state.manualActivities[index].date = date
                }
            }
        }
        return success
    }
    @discardableResult func logOption(_ option: MealOption, breakfast: Bool = false) -> Bool {
        reload()
        guard isReady else { return false }
        if breakfast, todayMeals.contains(where: \.isBreakfast) { return true }
        guard EntryValidation.meal(name: option.name, calories: option.calories, protein: option.protein, carbs: option.carbs, fat: option.fat) else {
            return reject(L10n.text("The meal estimate contains invalid values. Review your breakfast/target settings."))
        }
        let meal = Meal(date: currentDate, name: option.name, calories: option.calories, protein: option.protein,
                        carbs: option.carbs, fat: option.fat, isBreakfast: breakfast)
        context.insert(meal)
        let foods = option.ingredients.map { FoodItem(name: $0.name, grams: $0.grams, calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat) }
        for food in foods { context.insert(food) }
        meal.foods = foods
        meal.analysisSource = FoodAnalysisSource.recipe.rawValue
        if breakfast { day.breakfastStatus = "eaten" }
        return save()
    }
    func skipBreakfast() { reload(); guard isReady, loggedBreakfast == nil else { return }; day.breakfastStatus = "skipped"; save() }
    func restoreBreakfast() { reload(); guard isReady, loggedBreakfast == nil else { return }; day.breakfastStatus = "planned"; save() }
    func deleteMeal(_ meal: Meal) {
        if meal.isBreakfast && Calendar.current.isDate(meal.date, inSameDayAs: currentDate) { day.breakfastStatus = "planned" }
        context.delete(meal); save()
    }
    @discardableResult func logWeight(kilograms: Double, date: Date) -> Bool {
        guard isReady, EntryValidation.weight(kilograms), Calendar.current.startOfDay(for: date) <= currentDate else {
            return reject(L10n.text("Enter a weight from 20 to 400 kg for today or an earlier date."))
        }
        let day = Calendar.current.startOfDay(for: date)
        if let existing = weights.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
            existing.kilograms = kilograms; existing.source = "manual"
        } else { context.insert(WeightEntry(day: day, kilograms: kilograms)) }
        return save()
    }
    @discardableResult func logBadminton(date: Date) -> Bool {
        guard isReady else { return false }
        let day = Calendar.current.startOfDay(for: date)
        if !badminton.contains(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) { context.insert(BadmintonEntry(day: day)) }
        return save()
    }
    func deleteWorkout(_ workout: WorkoutSession) {
        let id = workout.id
        context.delete(workout)
        if save(), library.state.manualActivities.contains(where: { $0.workoutID == id }) {
            library.update { $0.manualActivities.removeAll { $0.workoutID == id } }
        }
    }
    func deleteBadminton(_ entry: BadmintonEntry) {
        let date = entry.day
        context.delete(entry)
        if save(), library.state.manualActivities.contains(where: { $0.badminton && Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            library.update { $0.manualActivities.removeAll { $0.badminton && Calendar.current.isDate($0.date, inSameDayAs: date) } }
        }
    }
    func deleteWeight(_ entry: WeightEntry) { context.delete(entry); save() }
    @discardableResult func addInventory(_ name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReady, !clean.isEmpty else { return false }
        if inventory.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) { return true }
        context.insert(FoodInventoryItem(name: clean)); return save()
    }
    func removeInventory(_ entry: FoodInventoryItem) { context.delete(entry); save() }

    func importHealthWeights(_ records: [HealthWeight]) {
        guard isReady else { return }
        for record in records.sorted(by: { $0.date < $1.date }) where EntryValidation.weight(record.kilograms) && record.date <= currentDate {
            let day = Calendar.current.startOfDay(for: record.date)
            if let existing = weights.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
                if existing.source != "manual" { existing.kilograms = record.kilograms }
            } else {
                let entry = WeightEntry(day: day, kilograms: record.kilograms, source: "Apple Health")
                context.insert(entry); weights.append(entry)
            }
        }
        if !records.isEmpty { save() }
    }
    func importHealthSleep(_ records: [HealthSleep]) {
        guard isReady else { return }
        for record in records where record.hours.isFinite && record.hours > 0 && record.hours <= 25 && record.day <= currentDate {
            if let existing = sleep.first(where: { Calendar.current.isDate($0.day, inSameDayAs: record.day) }) { existing.hours = record.hours }
            else { let entry = SleepEntry(day: record.day, hours: record.hours); context.insert(entry); sleep.append(entry) }
        }
        if !records.isEmpty { save() }
    }

    func exerciseAdvice(name: String) -> String {
        // Multiple load rows in one session are one performance observation, not separate sessions.
        let entries = workouts.filter { $0.date <= currentDate }.compactMap { session -> ExercisePerformance? in
            let rows = session.exercises.filter { TrainingCoach.canonical($0.name) == TrainingCoach.canonical(name) }
            guard !rows.isEmpty else { return nil }
            let completed = rows.allSatisfy { $0.reps >= $0.targetReps && $0.sets >= $0.targetSets && $0.sets > 0 }
            return ExercisePerformance(date: session.date, weight: rows.map(\.weightKG).max() ?? 0,
                sets: completed ? 1 : 0, reps: completed ? 1 : 0, targetReps: 1,
                rpe: rows.map(\.rpe).max() ?? 10,
                recordedVolume: rows.reduce(0) { $0 + $1.weightKG * Double($1.sets) * Double($1.reps) },
                targetSets: 1, recordedPerformance: rows.filter { $0.sets > 0 }.map { max($0.weightKG, 1) * Double($0.reps) }.max() ?? 0)
        }
        return FitnessLogic.progression(entries)
    }
    func exerciseProgress(name: String) -> String {
        let sessions = workouts.filter { $0.date <= currentDate && $0.exercises.contains { TrainingCoach.canonical($0.name) == TrainingCoach.canonical(name) } }
        guard let latest = sessions.first else { return L10n.text("No sessions logged.") }
        let rows = latest.exercises.sorted { $0.position < $1.position }.filter { TrainingCoach.canonical($0.name) == TrainingCoach.canonical(name) }
        let details = rows.map { L10n.text("%@ · %@ × %@", String(describing: weightText($0.weightKG)), String(describing: $0.sets), String(describing: $0.reps)) }.joined(separator: "; ")
        guard sessions.count > 1 else { return L10n.text("Latest: %@. First session is your baseline.", String(describing: details)) }
        func volume(_ session: WorkoutSession) -> Double {
            session.exercises.filter { TrainingCoach.canonical($0.name) == TrainingCoach.canonical(name) }.reduce(0) { $0 + $1.weightKG * Double($1.sets) * Double($1.reps) }
        }
        let previous = volume(sessions[1]), latestVolume = volume(latest)
        let change = previous > 0 ? L10n.text("%@ volume vs previous session", String(format: "%+.0f%%", locale: Locale.current, (latestVolume - previous) / previous * 100)) : L10n.text("Previous loaded volume unavailable")
        return L10n.text("Latest: %@. %@. Volume reflects changes in sets as well as performance.", String(describing: details), String(describing: change))
    }
    var recentExerciseNames: [String] {
        let names = workouts.filter { $0.date >= startOfRecentDays(7) && $0.date <= currentDate }.flatMap { $0.exercises.map(\.name) }
        var byName: [String: String] = [:]
        for name in names where byName[TrainingCoach.canonical(name)] == nil { byName[TrainingCoach.canonical(name)] = name }
        return byName.values.sorted()
    }
    var weeklyVolumeAdvice: String {
        let sets = workouts.filter { $0.date >= startOfRecentDays(7) && $0.date <= currentDate }.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
        if sets == 0 { return L10n.text("No completed sets logged this week. Record your own plan and review recovery if sessions were attempted.") }
        if sets < 10 { return L10n.text("%@ total sets logged this week. Check whether your full plan has been recorded; volume may be low.", String(describing: sets)) }
        if sets > 80 { return L10n.text("%@ total sets logged this week. Volume may be high; review recovery and exercise overlap.", String(describing: sets)) }
        return L10n.text("%@ total sets logged this week. Keep your own plan and review exercise-specific advice.", String(describing: sets))
    }
    var weeklySummaryText: String {
        let start = startOfRecentDays(7)
        let recent = meals.filter { $0.date >= start && $0.date <= currentDate }
        let loggedDays = Set(recent.map { Calendar.current.startOfDay(for: $0.date) }).count
        let calorieAverage = loggedDays == 0 ? "—" : String(format: "%.0f", recent.reduce(0) { $0 + $1.calories } / Double(loggedDays))
        let proteinAverage = loggedDays == 0 ? "—" : String(format: "%.0f", recent.reduce(0) { $0 + $1.protein } / Double(loggedDays))
        let gymCount = workouts.filter { $0.date >= start && $0.date <= currentDate }.count
        let dates = badminton.filter { $0.day >= start && $0.day <= currentDate }.map { $0.day.formatted(date: .abbreviated, time: .omitted) }.joined(separator: ", ")
        let sleepText = recentSleepAverage.map { L10n.text("%@ h", $0.formatted(.number.precision(.fractionLength(1)))) } ?? L10n.text("No readable Health sleep")
        let advice = recentExerciseNames.map { L10n.text("%@: %@\n%@", String(describing: $0), String(describing: exerciseProgress(name: $0)), String(describing: exerciseAdvice(name: $0))) }.joined(separator: "\n")
        return L10n.text("Last 7 calendar days\nNutrition recorded on %@/7 days\nAverage on logged days: %@ kcal · %@ g protein\nManually logged gym sessions: %@\nBadminton: %@\nAverage sleep (available nights): %@\nWeight: %@\n%@\n%@\n%@", String(describing: loggedDays), String(describing: calorieAverage), String(describing: proteinAverage), String(describing: gymCount), String(describing: dates.isEmpty ? L10n.text("None logged") : dates), String(describing: sleepText), String(describing: trend.label), String(describing: trend.advice), String(describing: weeklyVolumeAdvice), String(describing: advice))
    }
    func saveWeeklySummary() {
        let start = startOfRecentDays(7)
        if let existing = summaries.first(where: { $0.weekStart == start }) {
            existing.text = weeklySummaryText; existing.generatedAt = currentDate
        } else { context.insert(WeeklySummary(weekStart: start, text: weeklySummaryText)) }
        save()
    }
}
