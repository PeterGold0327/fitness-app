import Foundation

struct WeightPoint: Equatable {
    var date: Date
    var kilograms: Double
}

struct WeightTrend {
    var average: Double?
    var weeklyGain: Double?
    var label: String
    var advice: String
    var calorieAdjustment: Double?
}

struct ExercisePerformance {
    var date: Date
    var weight: Double
    var sets: Int
    var reps: Int
    var targetReps: Int
    var rpe: Double
    var recordedVolume: Double? = nil
    var targetSets: Int? = nil
    var recordedPerformance: Double? = nil
    var volume: Double { recordedVolume ?? weight * Double(sets) * Double(reps) }
    // Fewer planned sets alone do not indicate worse exercise performance.
    var performance: Double { recordedPerformance ?? max(weight, 1) * Double(reps) }
    var completedTargets: Bool { sets >= (targetSets ?? sets) && reps >= targetReps && sets > 0 }
    var valid: Bool {
        weight.isFinite && weight >= 0 && (0...30).contains(sets) && (0...100).contains(reps) &&
        (1...100).contains(targetReps) && (1...10).contains(rpe) &&
        (targetSets.map { (1...30).contains($0) } ?? true) &&
        (recordedPerformance.map { $0.isFinite && $0 >= 0 } ?? true)
    }
}

struct MealOption: Identifiable {
    var id: String { name }
    var name: String
    var ingredients: [Ingredient]
    var note: String
    var calories: Double { ingredients.reduce(0) { $0 + $1.calories } }
    var protein: Double { ingredients.reduce(0) { $0 + $1.protein } }
    var carbs: Double { ingredients.reduce(0) { $0 + $1.carbs } }
    var fat: Double { ingredients.reduce(0) { $0 + $1.fat } }
    var portionText: String { ingredients.map { "\($0.grams.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))) g \($0.name)" }.joined(separator: " + ") }
}

struct Ingredient {
    var name: String
    var grams: Double
    var caloriesPer100: Double
    var proteinPer100: Double
    var carbsPer100: Double
    var fatPer100: Double
    var calories: Double { grams * caloriesPer100 / 100 }
    var protein: Double { grams * proteinPer100 / 100 }
    var carbs: Double { grams * carbsPer100 / 100 }
    var fat: Double { grams * fatPer100 / 100 }
}

enum FitnessLogic {
    static func average(_ values: [Double]) -> Double? {
        let finite = values.filter(\.isFinite)
        return finite.isEmpty ? nil : finite.reduce(0, +) / Double(finite.count)
    }

    /// Calendar-day windows: missing days remain missing, rather than becoming zero kg.
    static func weightTrend(_ points: [WeightPoint], now: Date = .now, weeks: Int = 2,
                            calendar: Calendar = .current) -> WeightTrend {
        guard (2...4).contains(weeks) else {
            return WeightTrend(average: nil, weeklyGain: nil, label: "Invalid comparison window",
                               advice: "Use a two- or four-week comparison.", calorieAdjustment: nil)
        }
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let recentStart = calendar.date(byAdding: .day, value: -7, to: end)!
        let earlierStart = calendar.date(byAdding: .day, value: -(7 * weeks), to: end)!
        let earlierEnd = calendar.date(byAdding: .day, value: 7, to: earlierStart)!
        // One measurement per day, latest wins. UI and Health import also upsert by day.
        var daily: [Date: WeightPoint] = [:]
        for point in points.sorted(by: { $0.date < $1.date }) where point.kilograms.isFinite && point.kilograms > 0 && point.date <= now {
            daily[calendar.startOfDay(for: point.date)] = point
        }
        let recent = daily.values.filter { $0.date >= recentStart && $0.date < end }.map(\.kilograms)
        let earlier = daily.values.filter { $0.date >= earlierStart && $0.date < earlierEnd }.map(\.kilograms)
        let current = average(recent)
        guard weeks >= 2, recent.count >= 4, earlier.count >= 4,
              let current, let previous = average(earlier) else {
            return WeightTrend(average: current, weeklyGain: nil, label: "More weigh-ins needed",
                               advice: "Log at least 4 days in each comparison week. Targets stay unchanged.",
                               calorieAdjustment: nil)
        }
        let gain = (current - previous) / Double(weeks - 1)
        if gain < 0.1 - 1e-9 {
            return WeightTrend(average: current, weeklyGain: gain, label: "Too slow",
                               advice: "Consider adding 175 kcal/day. Confirm in Settings; targets never change automatically.",
                               calorieAdjustment: 175)
        }
        if gain > 0.25 + 1e-9 {
            return WeightTrend(average: current, weeklyGain: gain, label: "Too fast",
                               advice: "Consider reducing by 125 kcal/day. Confirm in Settings; targets never change automatically.",
                               calorieAdjustment: -125)
        }
        return WeightTrend(average: current, weeklyGain: gain, label: "On target",
                           advice: "Keep calories the same. Aim for roughly 0.1–0.25 kg/week.", calorieAdjustment: nil)
    }

    static func progression(_ history: [ExercisePerformance]) -> String {
        let recent = history.filter(\.valid).sorted { $0.date < $1.date }.suffix(3)
        guard let latest = recent.last else { return "Log a session to establish a baseline." }
        if recent.count == 3 {
            let entries = Array(recent)
            if entries[1].performance < entries[0].performance * 0.95 && entries[2].performance < entries[1].performance * 0.95 {
                return "Recorded per-set performance dropped in two consecutive sessions. Check for planned lighter days; otherwise maintain or reduce load by 5–10% and review recovery."
            }
        }
        if latest.completedTargets && latest.weight == 0 && latest.rpe <= 8 {
            return "Bodyweight targets completed. Try one more rep per set when comfortable."
        }
        if latest.completedTargets && latest.rpe <= 8 {
            return "Target reps completed at manageable RPE. Consider adding 1–2.5 kg next session."
        }
        if latest.completedTargets && latest.rpe < 9.5 {
            return "Keep the weight and try one more rep per set when comfortable."
        }
        return "Maintain workload until target reps feel controlled. Reduce load if form or recovery suffers."
    }

    static func legWarning(gymDate: Date, heavyLegs: Bool, badmintonDates: [Date]) -> String? {
        guard heavyLegs, badmintonDates.contains(where: { abs($0.timeIntervalSince(gymDate)) <= 48 * 3600 }) else { return nil }
        return "Badminton is within 48 hours of a heavy leg session. Consider a lighter leg day to protect court performance."
    }

    static func breakfast(yogurt: Double = 200, banana: Double = 120, oats: Double = 60) -> MealOption {
        // Typical supermarket labels; edit portions/macros to match the product you use.
        MealOption(name: "Daily breakfast", ingredients: [
            Ingredient(name: "Greek yogurt", grams: yogurt, caloriesPer100: 73, proteinPer100: 8.8, carbsPer100: 4, fatPer100: 2),
            Ingredient(name: "banana", grams: banana, caloriesPer100: 89, proteinPer100: 1.1, carbsPer100: 23, fatPer100: 0.3),
            Ingredient(name: "oats", grams: oats, caloriesPer100: 389, proteinPer100: 16.9, carbsPer100: 66, fatPer100: 6.9)
        ], note: "Greek yogurt + banana + oats; check your product labels.")
    }

    static func mealOptions(remainingCalories: Double, remainingProtein: Double, trained: Bool,
                            badminton: Bool, inventory: [String], trend: WeightTrend) -> [MealOption] {
        let activity = trained || badminton
        let portion = remainingCalories < 450 ? 0.55 : remainingCalories > 1100 && activity ? 1.2 : 1.0
        let proteinPortion = remainingProtein > 45 ? 1.2 : remainingProtein < 15 ? 0.7 : 1.0
        var options = [
            MealOption(name: "Chicken rice bowl", ingredients: [
                Ingredient(name: "chicken breast (cooked)", grams: 140 * proteinPortion, caloriesPer100: 165, proteinPer100: 31, carbsPer100: 0, fatPer100: 3.6),
                Ingredient(name: "rice (cooked)", grams: 220 * portion, caloriesPer100: 130, proteinPer100: 2.7, carbsPer100: 28, fatPer100: 0.3),
                Ingredient(name: "frozen vegetables", grams: 150, caloriesPer100: 40, proteinPer100: 2, carbsPer100: 6, fatPer100: 0.5),
                Ingredient(name: "olive oil", grams: 10 * portion, caloriesPer100: 884, proteinPer100: 0, carbsPer100: 0, fatPer100: 100)
            ], note: "Easy Coles, Woolworths or Aldi staples."),
            MealOption(name: "Eggs on toast + milk", ingredients: [
                Ingredient(name: "eggs (without shell)", grams: 150 * proteinPortion, caloriesPer100: 143, proteinPer100: 12.6, carbsPer100: 0.7, fatPer100: 9.5),
                Ingredient(name: "wholemeal bread", grams: 100 * portion, caloriesPer100: 247, proteinPer100: 13, carbsPer100: 41, fatPer100: 4.2),
                Ingredient(name: "milk", grams: 250, caloriesPer100: 50, proteinPer100: 3.5, carbsPer100: 5, fatPer100: 1.8)
            ], note: "Quick at-home option; no elaborate prep."),
            MealOption(name: "Yogurt, oats & banana", ingredients: breakfast(yogurt: 250 * proteinPortion, banana: 120 * portion, oats: 60 * portion).ingredients,
                       note: "An easy breakfast or snack from any Australian supermarket.")
        ]
        let stocked = inventory.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        func stockCount(_ option: MealOption) -> Int {
            option.ingredients.filter { ingredient in
                stocked.contains { inventoryMatches($0, ingredient: ingredient.name) }
            }.count
        }
        options.sort {
            let left = stockCount($0), right = stockCount($1)
            if left != right { return left > right }
            let leftFit = abs($0.calories - max(remainingCalories / 2, 250)) + max(0, remainingProtein / 2 - $0.protein) * 8
            let rightFit = abs($1.calories - max(remainingCalories / 2, 250)) + max(0, remainingProtein / 2 - $1.protein) * 8
            return leftFit < rightFit
        }
        for index in options.indices {
            if stockCount(options[index]) > 0 { options[index].note += " Uses food in your inventory." }
            if activity { options[index].note += " Include carbs to support today's activity." }
            if trend.calorieAdjustment != nil { options[index].note += " Weight trend: \(trend.label.lowercased()); review targets before changing them." }
            if remainingCalories > 0 && options[index].calories > remainingCalories {
                options[index].note += " This normal portion exceeds today's remaining calorie target; reduce portions or review the meal before logging."
            }
            if remainingCalories <= 0 && remainingProtein <= 0 { options[index].note += " Daily targets are met; eat according to hunger." }
        }
        return options
    }

    static func inventoryMatches(_ stocked: String, ingredient: String) -> Bool {
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter }.map { word in
                let token = String(word).replacingOccurrences(of: "yoghurt", with: "yogurt")
                return token.count > 3 && token.hasSuffix("s") ? String(token.dropLast()) : token
            })
        }
        let inventoryWords = words(stocked)
        return !inventoryWords.isEmpty && inventoryWords.isSubset(of: words(ingredient))
    }

    static func sleepNights(_ intervals: [DateInterval], now: Date, days: Int = 28,
                            calendar: Calendar = .current) -> [HealthSleep] {
        guard (1...366).contains(days) else { return [] }
        let start = calendar.startOfDay(for: now)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start),
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
                  let previousNoon = calendar.date(byAdding: .day, value: -1, to: noon) else { return nil }
            let clipped = intervals.compactMap { interval -> DateInterval? in
                let lower = max(interval.start, previousNoon), upper = min(interval.end, min(noon, now))
                return upper > lower ? DateInterval(start: lower, end: upper) : nil
            }
            return clipped.isEmpty ? nil : HealthSleep(day: day, hours: mergedHours(clipped))
        }
    }

    /// Merge overlapping Watch/iPhone sleep intervals instead of double counting them.
    static func mergedHours(_ intervals: [DateInterval]) -> Double {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var seconds = 0.0
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, next.end))
            } else {
                seconds += current.duration; current = next
            }
        }
        return (seconds + current.duration) / 3600
    }
}

// Framework-independent Health import values, also used by portable sleep tests.
struct HealthWeight { let date: Date; let kilograms: Double }
struct HealthSleep { let day: Date; let hours: Double }
struct HealthWorkout: Identifiable {
    let id: UUID
    let date: Date
    let minutes: Double
    let label: String
    var isGym = false
    var isBadminton = false
}

enum NumericInput {
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let decimal = locale.decimalSeparator ?? "."
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: decimal, with: ".")
        // Do not accept grouping, exponents, partial values or stale previous input.
        guard normalized.range(of: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)$", options: .regularExpression) != nil,
              let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}

enum EntryValidation {
    static func meal(name: String, calories: Double, protein: Double, carbs: Double, fat: Double) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        calories.isFinite && (0...20000).contains(calories) &&
        [protein, carbs, fat].allSatisfy { $0.isFinite && (0...3000).contains($0) }
    }
    static func weight(_ kilograms: Double) -> Bool { kilograms.isFinite && (20...400).contains(kilograms) }
    static func profile(height: Double, startingWeight: Double, calories: Double, protein: Double,
                        fat: Double, yogurt: Double, banana: Double, oats: Double) -> Bool {
        [height, startingWeight, calories, protein, fat, yogurt, banana, oats].allSatisfy(\.isFinite) &&
        (100...250).contains(height) && weight(startingWeight) && (1000...6000).contains(calories) &&
        (30...300).contains(protein) && (20...200).contains(fat) &&
        [yogurt, banana, oats].allSatisfy { (0...1000).contains($0) } &&
        yogurt + banana + oats > 0 && protein * 4 + fat * 9 <= calories
    }
}

extension Double {
    /// Display corrupt/non-finite values without an Int-conversion trap.
    var wholeText: String {
        isFinite ? formatted(.number.grouping(.never).precision(.fractionLength(0))) : "—"
    }
}
