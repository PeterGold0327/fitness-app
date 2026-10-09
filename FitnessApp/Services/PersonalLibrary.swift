import Foundation

struct SavedMealTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var items: [EstimatedFoodItem] = []
    var valid: Bool {
        EntryValidation.meal(name: name, calories: calories, protein: protein, carbs: carbs, fat: fat) &&
        (items.isEmpty || FoodEstimate(name: name, items: items, confidence: 0, uncertaintyNotes: "").valid &&
         abs(items.reduce(0) { $0 + $1.calories } - calories) < 0.001 &&
         abs(items.reduce(0) { $0 + $1.protein } - protein) < 0.001 &&
         abs(items.reduce(0) { $0 + $1.carbs } - carbs) < 0.001 &&
         abs(items.reduce(0) { $0 + $1.fat } - fat) < 0.001)
    }
}
struct ManualActivityRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var badminton: Bool
    var workoutID: UUID? = nil
    var minutes: Double
    var activeCalories: Double? = nil
    var valid: Bool { minutes.isFinite && (1...600).contains(minutes) && (activeCalories.map { $0.isFinite && (0...10000).contains($0) } ?? true) }
}
struct PersonalLibraryState: Codable {
    var version = 1
    var workouts = WorkoutTemplate.defaults
    var meals: [SavedMealTemplate] = []
    var manualActivities: [ManualActivityRecord] = []
    var goalWeightKG: Double? = nil
    var plannedSplit: TrainingSplit? = nil
    var plannedDate: Date? = nil
    var valid: Bool {
        version == 1 && manualActivities.count <= 1000 && manualActivities.allSatisfy(\.valid) && (goalWeightKG.map(EntryValidation.weight) ?? true) && workouts.count == 4 && Set(workouts.map(\.id)) == Set(TrainingSplit.allCases) &&
        workouts.allSatisfy(\.valid) && meals.count <= 100 && Set(meals.map(\.id)).count == meals.count && meals.allSatisfy(\.valid)
    }
}
/// Versioned preferences only; never edits or recreates the SwiftData database.
struct PersonalLibraryPersistence {
    var defaults: UserDefaults
    static let key = "leanlog.personalLibrary.v1"
    func load() throws -> PersonalLibraryState {
        guard let data = defaults.data(forKey: Self.key) else { return PersonalLibraryState() }
        let state = try JSONDecoder().decode(PersonalLibraryState.self, from: data)
        guard state.valid else { throw CocoaError(.coderReadCorrupt) }
        return state
    }
    func save(_ state: PersonalLibraryState) throws {
        guard state.valid else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(state), forKey: Self.key)
    }
}
