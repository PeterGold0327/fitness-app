import Foundation

struct CoachNutrition: Equatable { var calories: Double; var protein: Double }
struct DailyCoachInput {
    var nutrition: CoachNutrition?
    var calorieTarget: Double
    var proteinTarget: Double
    var plannedTraining: String? = nil
    var trained = false
    var hasTrainingHistory = false
    var badminton = false
    var sleepHours: Double? = nil
    var activeCalories: Double? = nil
    var usualActiveCalories: Double? = nil
    var trend: WeightTrend? = nil
}
struct CoachAction: Identifiable, Equatable {
    enum Kind: String { case training, nutrition, activity, recovery, weight, logMeal }
    var kind: Kind
    var text: String
    var id: String { kind.rawValue }
}
enum DailyCoach {
    static func highActivity(_ input: DailyCoachInput) -> Bool {
        guard let energy = input.activeCalories, energy.isFinite, energy >= 0 else { return false }
        if let usual = input.usualActiveCalories, usual.isFinite, usual > 0 {
            return energy >= max(600, usual * 1.5 + 150)
        }
        return energy >= 800
    }
    /// Only observed data is used. Targets are never changed by a recommendation.
    static func actions(_ input: DailyCoachInput) -> [CoachAction] {
        guard input.calorieTarget.isFinite, input.proteinTarget.isFinite,
              (1000...6000).contains(input.calorieTarget), (30...300).contains(input.proteinTarget) else {
            return [CoachAction(kind: .nutrition, text: L10n.text("Review your daily targets in Settings before using nutrition advice."))]
        }
        var candidates: [CoachAction] = []
        let shortSleep = input.sleepHours.map { $0.isFinite && $0 > 0 && $0 < 6 } ?? false
        if let plan = input.plannedTraining, !input.trained {
            candidates.append(CoachAction(kind: .training, text: shortSleep
                ? L10n.text("Today: %@. Sleep was short; use comfortable loads and focus on completing your session.", L10n.text(plan))
                : input.hasTrainingHistory
                    ? L10n.text("Today: %@. Start with your previous performance and aim for one or two more reps.", L10n.text(plan))
                    : L10n.text("Today: %@. Choose a comfortable first load and record your actual reps.", L10n.text(plan))))
        }
        if let nutrition = input.nutrition, nutrition.calories.isFinite, nutrition.protein.isFinite,
           nutrition.calories >= 0, nutrition.protein >= 0 {
            let protein = max(0, input.proteinTarget - nutrition.protein)
            let calories = max(0, input.calorieTarget - nutrition.calories)
            if protein >= 20 {
                candidates.append(CoachAction(kind: .nutrition, text: L10n.text("About %@ g protein remains in your logged target. Prioritize protein in your next meal.", String(Int(protein.rounded())))))
            }
            if highActivity(input) {
                candidates.append(CoachAction(kind: .activity, text: calories < 200
                    ? L10n.text("Activity is high, but logged calories are near your target. Do not automatically eat back all exercise calories.")
                    : L10n.text("Activity is high today. Include carbs and protein in your next meal; do not automatically eat back all exercise calories.")))
            } else if input.badminton {
                candidates.append(CoachAction(kind: .activity, text: L10n.text("Badminton is recorded today. Include carbs and protein around activity, within your usual targets.")))
            }
            if candidates.isEmpty, calories > 300 {
                candidates.append(CoachAction(kind: .nutrition, text: L10n.text("About %@ kcal remains based on logged meals. Choose one balanced meal next.", String(Int((calories / 50).rounded() * 50)))))
            }
        } else {
            candidates.append(CoachAction(kind: .logMeal, text: L10n.text("Log your first meal to get a useful nutrition suggestion. Unlogged food is not counted as zero intake.")))
            if highActivity(input) {
                candidates.append(CoachAction(kind: .activity, text: L10n.text("Activity is high today. Include carbs and protein in your next meal; do not automatically eat back all exercise calories.")))
            }
        }
        if shortSleep {
            candidates.append(CoachAction(kind: .recovery, text: L10n.text("Sleep was short. Keep training comfortable today and leave room for recovery.")))
        }
        if let trend = input.trend, trend.weeklyGain != nil {
            candidates.append(CoachAction(kind: .weight, text: trend.advice))
        }
        if candidates.isEmpty {
            candidates.append(CoachAction(kind: .nutrition, text: L10n.text("Logged nutrition is close to your targets. Eat according to hunger and keep your usual plan.")))
        }
        return Array(candidates.prefix(2))
    }
    /// One meal, with a conservative carbohydrate emphasis rather than calorie reimbursement.
    static func meal(_ options: [MealOption], input: DailyCoachInput) -> MealOption? {
        guard var meal = options.first else { return nil }
        if highActivity(input), let nutrition = input.nutrition,
           input.calorieTarget - nutrition.calories > meal.calories + 150 {
            if let rice = meal.ingredients.firstIndex(where: { $0.name == "rice (cooked)" }) {
                meal.ingredients[rice].grams += 50
            }
            meal.note = L10n.text("A little extra carbohydrate supports today's activity. Your daily target is unchanged.")
        }
        return meal
    }
}
