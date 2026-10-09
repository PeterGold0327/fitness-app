import Foundation
import SwiftData

@Model final class UserProfile {
    var name: String = "Me"
    var heightCM: Double = 178
    var startingWeightKG: Double = 63
    var calorieTarget: Double = 2700
    var proteinTarget: Double = 130
    var fatTarget: Double = 70
    var usesPounds: Bool = false
    var breakfastYogurtGrams: Double = 200
    var breakfastBananaGrams: Double = 120
    var breakfastOatsGrams: Double = 60
    init() {}
}

@Model final class DailyNutrition {
    @Attribute(.unique) var day: Date
    /// planned, eaten, or skipped. Planned breakfast is NOT counted in eaten totals.
    var breakfastStatus: String = "planned"
    init(day: Date) { self.day = Calendar.current.startOfDay(for: day) }
}

@Model final class Meal {
    var id: UUID = UUID()
    var date: Date
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var isBreakfast: Bool
    /// Empty means a legacy/time-inferred category; no meal record is duplicated.
    var mealCategory: String = ""
    var analysisSource: String = "manual"
    var analysisConfidence: Double? = nil
    var analysisNotes: String = ""
    @Attribute(.externalStorage) var photoData: Data?
    @Relationship(deleteRule: .cascade, inverse: \FoodItem.meal) var foods: [FoodItem] = []
    init(date: Date = .now, name: String, calories: Double, protein: Double,
         carbs: Double = 0, fat: Double = 0, isBreakfast: Bool = false, photoData: Data? = nil) {
        self.date = date; self.name = name; self.calories = calories
        self.protein = protein; self.carbs = carbs; self.fat = fat
        self.isBreakfast = isBreakfast; self.photoData = photoData
    }
}

@Model final class FoodItem {
    var meal: Meal? = nil
    var name: String
    var grams: Double
    var carbs: Double = 0
    var fat: Double = 0
    var confidence: Double? = nil
    var uncertaintyNotes: String = ""
    var position: Int = 0
    var calories: Double
    var protein: Double
    init(name: String, grams: Double, calories: Double, protein: Double, carbs: Double = 0, fat: Double = 0, confidence: Double? = nil, uncertaintyNotes: String = "") {
        self.name = name; self.grams = grams; self.calories = calories; self.protein = protein
        self.carbs = carbs; self.fat = fat; self.confidence = confidence; self.uncertaintyNotes = uncertaintyNotes
    }
}

@Model final class WeightEntry {
    @Attribute(.unique) var day: Date
    var kilograms: Double
    var source: String
    init(day: Date = .now, kilograms: Double, source: String = "manual") {
        self.day = Calendar.current.startOfDay(for: day); self.kilograms = kilograms; self.source = source
    }
}

@Model final class WorkoutSession {
    var id: UUID = UUID()
    var date: Date
    var name: String
    @Relationship(deleteRule: .cascade, inverse: \ExerciseEntry.session) var exercises: [ExerciseEntry] = []
    init(date: Date = .now, name: String = "Gym") { self.date = date; self.name = name }
}

@Model final class ExerciseEntry {
    var session: WorkoutSession? = nil
    var position: Int = 0
    var name: String
    var weightKG: Double
    var sets: Int
    var reps: Int
    var targetReps: Int
    var targetSets: Int = 3
    var rpe: Double
    var isLegExercise: Bool
    var notes: String
    init(name: String, weightKG: Double, sets: Int, reps: Int, targetReps: Int,
         rpe: Double, targetSets: Int? = nil, isLegExercise: Bool = false, notes: String = "") {
        self.name = name; self.weightKG = weightKG; self.sets = sets; self.reps = reps
        self.targetReps = targetReps; self.targetSets = targetSets ?? sets; self.rpe = rpe; self.isLegExercise = isLegExercise; self.notes = notes
    }
}

@Model final class SleepEntry {
    @Attribute(.unique) var day: Date
    var hours: Double
    init(day: Date, hours: Double) {
        self.day = Calendar.current.startOfDay(for: day); self.hours = hours
    }
}

@Model final class BadmintonEntry {
    @Attribute(.unique) var day: Date
    init(day: Date = .now) { self.day = Calendar.current.startOfDay(for: day) }
}

@Model final class FoodInventoryItem {
    var name: String
    init(name: String) { self.name = name }
}

@Model final class WeeklySummary {
    @Attribute(.unique) var weekStart: Date
    var generatedAt: Date
    var text: String
    init(weekStart: Date, text: String) {
        self.weekStart = weekStart; self.generatedAt = .now; self.text = text
    }
}

// Only archive-specific metadata is stored; existing fitness records remain canonical.
@Model final class GrowthMilestone {
    @Attribute(.unique) var key: String
    var date: Date
    var kind: String
    var title: String
    var detail: String
    var isAutomatic: Bool
    init(key: String = UUID().uuidString, date: Date, kind: String = "manual", title: String, detail: String, isAutomatic: Bool = false) {
        self.key = key; self.date = date; self.kind = kind; self.title = title; self.detail = detail; self.isAutomatic = isAutomatic
    }
}

@Model final class ProgressPhoto {
    var id: UUID = UUID()
    var date: Date
    var angle: String
    var notes: String
    @Attribute(.externalStorage) var photoData: Data?
    init(date: Date, angle: String, notes: String = "", photoData: Data) {
        self.date = date; self.angle = angle; self.notes = notes; self.photoData = photoData
    }
}
