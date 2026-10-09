import Foundation

// Transient projections of SwiftData records, never a second timeline database.
enum TimelinePeriod: String, CaseIterable, Sendable {
    case day, week, month, year
    var label: String {
        switch self {
        case .day: return L10n.text("Day")
        case .week: return L10n.text("Week")
        case .month: return L10n.text("Month")
        case .year: return L10n.text("Year")
        }
    }
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
    func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: component, for: date)!
    }
}

enum ProgressPhotoAngle: String, CaseIterable, Sendable {
    case front, side, back
    var label: String {
        switch self {
        case .front: return L10n.text("Front")
        case .side: return L10n.text("Side")
        case .back: return L10n.text("Back")
        }
    }
}

enum TimelineMealCategory: String, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack
    var label: String {
        switch self {
        case .breakfast: return L10n.text("Breakfast")
        case .lunch: return L10n.text("Lunch")
        case .dinner: return L10n.text("Dinner")
        case .snack: return L10n.text("Snacks")
        }
    }
    static func infer(date: Date, isBreakfast: Bool, calendar: Calendar) -> Self {
        if isBreakfast { return .breakfast }
        switch calendar.component(.hour, from: date) {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<21: return .dinner
        default: return .snack
        }
    }
}

struct TimelineFood: Sendable {
    var name: String; var grams: Double
    var calories: Double; var protein: Double; var carbs: Double; var fat: Double
    var confidence: Double?; var notes: String
}
struct TimelineMeal: Identifiable, Sendable {
    var id: UUID; var date: Date; var name: String; var category: TimelineMealCategory
    var calories: Double; var protein: Double; var carbs: Double; var fat: Double
    var foods: [TimelineFood] = []; var photo: Data? = nil
}
struct TimelineExercise: Sendable {
    var name: String; var weight: Double; var sets: Int; var reps: Int; var rpe: Double; var notes: String
    /// A descriptive per-set score, not estimated strength or total session volume.
    var score: Double { sets > 0 && reps > 0 ? max(weight, 1) * Double(reps) : 0 }
}
struct TimelineWorkout: Identifiable, Sendable {
    var id: UUID; var date: Date; var name: String; var exercises: [TimelineExercise]
}
struct TimelineWeight: Sendable { var date: Date; var kilograms: Double }
struct TimelineSleep: Sendable { var date: Date; var hours: Double }
struct TimelinePhoto: Identifiable, Sendable {
    var id: UUID; var date: Date; var angle: ProgressPhotoAngle; var notes: String; var data: Data
}
struct TimelineMilestone: Identifiable, Sendable {
    var id: String; var date: Date; var kind: String; var title: String; var detail: String
}
struct TimelineHistory: Sendable {
    var meals: [TimelineMeal] = []
    var weights: [TimelineWeight] = []
    var sleep: [TimelineSleep] = []
    var workouts: [TimelineWorkout] = []
    var badminton: [Date] = []
    var photos: [TimelinePhoto] = []
    var milestones: [TimelineMilestone] = []
    var calorieTarget: Double = 2700
    var proteinTarget: Double = 130
}
struct TimelineDay: Identifiable, Sendable {
    var date: Date; var weight: Double?; var weightAverage: Double?; var weightSampleCount: Int
    var sleep: Double?; var meals: [TimelineMeal]; var workouts: [TimelineWorkout]
    var badminton: Bool; var photos: [TimelinePhoto]; var milestones: [TimelineMilestone]
    var id: Date { date }
    var calories: Double { meals.reduce(0) { $0 + $1.calories } }
    var protein: Double { meals.reduce(0) { $0 + $1.protein } }
    var carbs: Double { meals.reduce(0) { $0 + $1.carbs } }
    var fat: Double { meals.reduce(0) { $0 + $1.fat } }
    var hasRecords: Bool { weight != nil || sleep != nil || !meals.isEmpty || !workouts.isEmpty || badminton || !photos.isEmpty || !milestones.isEmpty }
    var summary: String {
        guard hasRecords else { return L10n.text("No records in this period.") }
        var parts: [String] = []
        if let weight { parts.append(L10n.text("Weight: %@ kg", GrowthTimeline.number(weight))) }
        if let sleep { parts.append(L10n.text("Sleep: %@ h", GrowthTimeline.number(sleep))) }
        if !meals.isEmpty { parts.append(L10n.text("%@ meals · %@ kcal · %@ g protein", String(meals.count), GrowthTimeline.number(calories), GrowthTimeline.number(protein))) }
        if !workouts.isEmpty { parts.append(L10n.text("%@ gym sessions", String(workouts.count))) }
        if badminton { parts.append(L10n.text("Badminton logged")) }
        if !photos.isEmpty { parts.append(L10n.text("%@ progress photos", String(photos.count))) }
        if !milestones.isEmpty { parts.append(L10n.text("%@ milestones", String(milestones.count))) }
        return parts.joined(separator: " · ")
    }
}
struct TimelineExerciseProgress: Identifiable, Sendable {
    var name: String; var first: TimelineExercise; var latest: TimelineExercise; var best: TimelineExercise
    var id: String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var summary: String {
        L10n.text("%@: first %@ kg × %@ → latest %@ kg × %@; best %@ kg × %@", name,
                  GrowthTimeline.number(first.weight), String(first.reps), GrowthTimeline.number(latest.weight), String(latest.reps),
                  GrowthTimeline.number(best.weight), String(best.reps))
    }
}
struct TimelineSummary: Sendable {
    var days: [TimelineDay]; var calendarDays: Int
    var startingWeight: Double?; var endingWeight: Double?; var averageWeight: Double?
    var averageCalories: Double?; var averageProtein: Double?; var nutritionDays: Int
    var calorieAdherentDays: Int; var proteinAdherentDays: Int; var jointlyAdherentDays: Int
    var gymSessions: Int; var badmintonDays: Int; var averageSleep: Double?; var sleepNights: Int
    var exercises: [TimelineExerciseProgress]
    var text: String {
        guard !days.isEmpty else { return L10n.text("No records in this period.") }
        return L10n.text("Nutrition recorded on %@/%@ days; averages on logged days: %@ kcal · %@ g protein. Gym: %@ sessions; badminton: %@ days. Sleep: %@ h across %@ nights. Both nutrition targets met on %@ logged days.",
                         String(nutritionDays), String(calendarDays), averageCalories.map(GrowthTimeline.number) ?? L10n.text("—"),
                         averageProtein.map(GrowthTimeline.number) ?? L10n.text("—"), String(gymSessions), String(badmintonDays),
                         averageSleep.map(GrowthTimeline.number) ?? L10n.text("—"), String(sleepNights), String(jointlyAdherentDays))
    }
    func exerciseComparisons(with previous: TimelineSummary) -> [String] {
        exercises.compactMap { exercise in
            guard let earlier = previous.exercises.first(where: { $0.id == exercise.id }) else { return nil }
            return L10n.text("%@: previous best %@ kg × %@ → current best %@ kg × %@", exercise.name,
                             GrowthTimeline.number(earlier.best.weight), String(earlier.best.reps),
                             GrowthTimeline.number(exercise.best.weight), String(exercise.best.reps))
        }
    }
    func comparison(with previous: TimelineSummary) -> String {
        func delta(_ current: Double?, _ previous: Double?) -> String {
            guard let current, let previous else { return L10n.text("—") }
            return String(format: "%+.1f", locale: Locale.current, current - previous)
        }
        return L10n.text("Compared with previous period: average weight %@ kg; calories %@ kcal; protein %@ g; sleep %@ h; gym sessions %@.",
                         delta(averageWeight, previous.averageWeight), delta(averageCalories, previous.averageCalories),
                         delta(averageProtein, previous.averageProtein), delta(averageSleep, previous.averageSleep),
                         previous.days.isEmpty ? L10n.text("—") : String(gymSessions - previous.gymSessions))
    }
}

enum GrowthTimeline {
    static func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
    static func contains(_ date: Date, in interval: DateInterval) -> Bool { date >= interval.start && date < interval.end }
    static func day(_ date: Date, history: TimelineHistory, calendar: Calendar, asOf: Date) -> TimelineDay {
        let start = calendar.startOfDay(for: date)
        let interval = TimelinePeriod.day.interval(containing: start, calendar: calendar)
        func onDay(_ date: Date) -> Bool { date <= asOf && contains(date, in: interval) }
        let weights = history.weights.filter { $0.date <= asOf && EntryValidation.weight($0.kilograms) }
        let recentStart = calendar.date(byAdding: .day, value: -6, to: start)!
        let recent = weights.filter { $0.date >= recentStart && $0.date < interval.end }
        return TimelineDay(date: start,
                           weight: weights.filter { onDay($0.date) }.sorted { $0.date < $1.date }.last?.kilograms,
                           weightAverage: FitnessLogic.average(recent.map(\.kilograms)), weightSampleCount: recent.count,
                           sleep: history.sleep.filter { onDay($0.date) && $0.hours.isFinite && $0.hours > 0 }.first?.hours,
                           meals: history.meals.filter { onDay($0.date) }.sorted { $0.date < $1.date },
                           workouts: history.workouts.filter { onDay($0.date) }.sorted { $0.date < $1.date },
                           badminton: history.badminton.contains(where: onDay),
                           photos: history.photos.filter { onDay($0.date) }.sorted { $0.date < $1.date },
                           milestones: history.milestones.filter { onDay($0.date) }.sorted { $0.id < $1.id })
    }
    static func recordedDates(history: TimelineHistory, calendar: Calendar, asOf: Date) -> [Date] {
        let dates = history.meals.map(\.date) + history.weights.map(\.date) + history.sleep.map(\.date) +
        history.workouts.map(\.date) + history.badminton + history.photos.map(\.date) + history.milestones.map(\.date)
        return Set(dates.filter { $0 <= asOf }.map { calendar.startOfDay(for: $0) }).sorted()
    }
    static func days(history: TimelineHistory, interval: DateInterval?, calendar: Calendar, asOf: Date) -> [TimelineDay] {
        let dates = recordedDates(history: history, calendar: calendar, asOf: asOf)
            .filter { date in interval.map { contains(date, in: $0) } ?? true }
        // Group once for long archives rather than rescan every meal/photo for every day.
        let meals = Dictionary(grouping: history.meals, by: { calendar.startOfDay(for: $0.date) })
        let sleep = Dictionary(grouping: history.sleep, by: { calendar.startOfDay(for: $0.date) })
        let workouts = Dictionary(grouping: history.workouts, by: { calendar.startOfDay(for: $0.date) })
        let photos = Dictionary(grouping: history.photos, by: { calendar.startOfDay(for: $0.date) })
        let milestones = Dictionary(grouping: history.milestones, by: { calendar.startOfDay(for: $0.date) })
        let badminton = Dictionary(grouping: history.badminton, by: { calendar.startOfDay(for: $0) })
        let weights = history.weights.filter { $0.date <= asOf && EntryValidation.weight($0.kilograms) }.sorted { $0.date < $1.date }
        var lower = 0, upper = 0
        return dates.compactMap { date in
            let recentStart = calendar.date(byAdding: .day, value: -6, to: date)!
            let end = calendar.date(byAdding: .day, value: 1, to: date)!
            while lower < weights.count && weights[lower].date < recentStart { lower += 1 }
            upper = max(upper, lower)
            while upper < weights.count && weights[upper].date < end { upper += 1 }
            var bucket = TimelineHistory()
            bucket.meals = meals[date] ?? []; bucket.weights = Array(weights[lower..<upper])
            bucket.sleep = sleep[date] ?? []; bucket.workouts = workouts[date] ?? []
            bucket.photos = photos[date] ?? []; bucket.milestones = milestones[date] ?? []
            bucket.badminton = badminton[date] ?? []
            let result = day(date, history: bucket, calendar: calendar, asOf: asOf)
            return result.hasRecords ? result : nil
        }
    }
    static func meetsCalorieTarget(_ value: Double, target: Double) -> Bool {
        target.isFinite && target > 0 && value >= target * 0.9 && value <= target * 1.1
    }
    static func summary(history: TimelineHistory, interval: DateInterval, calendar: Calendar, asOf: Date) -> TimelineSummary {
        let days = days(history: history, interval: interval, calendar: calendar, asOf: asOf)
        let nutrition = days.filter { !$0.meals.isEmpty }
        let weights = days.compactMap(\.weight)
        let sleep = days.compactMap(\.sleep)
        let workouts = days.flatMap(\.workouts).sorted { $0.date < $1.date }
        let calorieDays = nutrition.filter { meetsCalorieTarget($0.calories, target: history.calorieTarget) }
        let proteinDays = nutrition.filter { history.proteinTarget > 0 && $0.protein >= history.proteinTarget }
        let both = nutrition.filter { meetsCalorieTarget($0.calories, target: history.calorieTarget) && history.proteinTarget > 0 && $0.protein >= history.proteinTarget }
        var exerciseRows: [String: [(Date, TimelineExercise)]] = [:]
        for workout in workouts {
            for row in workout.exercises where row.score > 0 {
                exerciseRows[row.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), default: []].append((workout.date, row))
            }
        }
        let progress = exerciseRows.keys.sorted().compactMap { name -> TimelineExerciseProgress? in
            let rows = exerciseRows[name]!.sorted { $0.0 < $1.0 }
            guard let firstDate = rows.first?.0, let lastDate = rows.last?.0 else { return nil }
            let first = rows.filter { $0.0 == firstDate }.map { $0.1 }.max { $0.score < $1.score }!
            let latest = rows.filter { $0.0 == lastDate }.map { $0.1 }.max { $0.score < $1.score }!
            return TimelineExerciseProgress(name: latest.name, first: first, latest: latest, best: rows.map { $0.1 }.max { $0.score < $1.score }!)
        }
        // Calendar arithmetic preserves 23/25-hour days and variable-length months.
        let end = min(interval.end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: asOf))!)
        let count = end > interval.start ? calendar.dateComponents([.day], from: interval.start, to: end).day ?? 0 : 0
        return TimelineSummary(days: days, calendarDays: count, startingWeight: weights.first, endingWeight: weights.last,
                               averageWeight: FitnessLogic.average(weights), averageCalories: FitnessLogic.average(nutrition.map(\.calories)),
                               averageProtein: FitnessLogic.average(nutrition.map(\.protein)), nutritionDays: nutrition.count,
                               calorieAdherentDays: calorieDays.count, proteinAdherentDays: proteinDays.count, jointlyAdherentDays: both.count,
                               gymSessions: workouts.count, badmintonDays: days.filter(\.badminton).count,
                               averageSleep: FitnessLogic.average(sleep), sleepNights: sleep.count, exercises: progress)
    }
    static func onThisDay(history: TimelineHistory, date: Date, calendar: Calendar) -> [TimelineDay] {
        let month = calendar.component(.month, from: date), dayOfMonth = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        return recordedDates(history: history, calendar: calendar, asOf: date).filter {
            calendar.component(.year, from: $0) < year && calendar.component(.month, from: $0) == month && calendar.component(.day, from: $0) == dayOfMonth
        }.map { day($0, history: history, calendar: calendar, asOf: date) }.reversed()
    }
    static func photoComparison(_ photos: [TimelinePhoto], angle: ProgressPhotoAngle, monthsAgo: Int? = nil,
                                weeksAgo: Int? = nil, asOf: Date, calendar: Calendar) -> (earlier: TimelinePhoto, later: TimelinePhoto)? {
        let available = photos.filter { $0.angle == angle && $0.date <= asOf }.sorted { $0.date < $1.date }
        guard let latest = available.last else { return nil }
        let target: Date?
        if let monthsAgo { target = calendar.date(byAdding: .month, value: -monthsAgo, to: asOf) }
        else if let weeksAgo { target = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: asOf) }
        else { target = nil }
        let earlier: TimelinePhoto?
        if let target {
            // Select only the requested calendar week/month, never silently use a distant photo.
            let interval = (monthsAgo != nil ? TimelinePeriod.month : .week).interval(containing: target, calendar: calendar)
            earlier = available.filter { contains($0.date, in: interval) && $0.id != latest.id }.last
            let current = (monthsAgo != nil ? TimelinePeriod.month : .week).interval(containing: asOf, calendar: calendar)
            guard contains(latest.date, in: current) else { return nil }
        } else { earlier = available.first }
        guard let earlier, earlier.id != latest.id else { return nil }
        return (earlier, latest)
    }
}
