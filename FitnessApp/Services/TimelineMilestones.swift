import Foundation

extension GrowthTimeline {
    /// Stable keys allow SwiftData to reconcile metadata without copying source records.
    static func automaticMilestones(history: TimelineHistory, calendar: Calendar, asOf: Date) -> [TimelineMilestone] {
        var result: [TimelineMilestone] = []
        let weights = history.weights.filter { $0.date <= asOf && EntryValidation.weight($0.kilograms) }.sorted { $0.date < $1.date }
        if let first = weights.first {
            var high = first.kilograms, low = first.kilograms
            for weight in weights.dropFirst() {
                if Int(floor(weight.kilograms)) > Int(floor(high)) {
                    for kg in (Int(floor(high)) + 1)...Int(floor(weight.kilograms)) {
                        result.append(TimelineMilestone(id: "weight-up-\(kg)", date: weight.date, kind: "weight",
                            title: L10n.text("New weight milestone"), detail: L10n.text("First recorded weigh-in at or above %@ kg.", String(kg))))
                    }
                }
                if Int(ceil(weight.kilograms)) < Int(ceil(low)) {
                    for kg in Int(ceil(weight.kilograms))..<Int(ceil(low)) {
                        result.append(TimelineMilestone(id: "weight-down-\(kg)", date: weight.date, kind: "weight",
                            title: L10n.text("New weight milestone"), detail: L10n.text("First recorded weigh-in at or below %@ kg.", String(kg))))
                    }
                }
                high = max(high, weight.kilograms); low = min(low, weight.kilograms)
            }
        }
        let workouts = history.workouts.filter { $0.date <= asOf }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
        var best: [String: Double] = [:]
        for workout in workouts {
            let grouped = Dictionary(grouping: workout.exercises.filter { $0.score > 0 }, by: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            for name in grouped.keys.sorted() {
                let row = grouped[name]!.max { $0.score < $1.score }!
                if let previous = best[name], row.score > previous {
                    result.append(TimelineMilestone(id: "exercise-\(workout.id.uuidString)-\(name)", date: workout.date, kind: "exercise",
                        title: L10n.text("New exercise best"),
                        detail: L10n.text("%@: %@ kg × %@ reps. Best recorded load × reps per set; not a strength prediction.", row.name, number(row.weight), String(row.reps))))
                }
                best[name] = max(best[name] ?? 0, row.score)
            }
        }
        let trainingWeeks = Set(workouts.filter { $0.exercises.contains { $0.score > 0 } }.map {
            TimelinePeriod.week.interval(containing: $0.date, calendar: calendar).start
        }).sorted()
        var streak = 0, previousWeek: Date?
        for week in trainingWeeks {
            streak = previousWeek.flatMap { calendar.date(byAdding: .weekOfYear, value: 1, to: $0) } == week ? streak + 1 : 1
            if streak % 4 == 0 {
                let interval = TimelinePeriod.week.interval(containing: week, calendar: calendar)
                let last = workouts.filter { contains($0.date, in: interval) && $0.exercises.contains { $0.score > 0 } }.last!
                result.append(TimelineMilestone(id: "training-\(dateKey(week, calendar: calendar))", date: last.date, kind: "training",
                    title: L10n.text("Consistent training"), detail: L10n.text("At least one completed gym session in each of %@ consecutive calendar weeks.", String(streak))))
            }
            previousWeek = week
        }
        // Only completed calendar days count toward nutrition streaks.
        let completedDays = days(history: history, interval: nil, calendar: calendar, asOf: asOf).filter {
            $0.date < calendar.startOfDay(for: asOf) && !$0.meals.isEmpty
        }
        var nutritionStreak = 0, previousDay: Date?
        for day in completedDays {
            let meets = meetsCalorieTarget(day.calories, target: history.calorieTarget) && history.proteinTarget > 0 && day.protein >= history.proteinTarget
            let contiguous = previousDay.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day.date
            nutritionStreak = meets ? (contiguous ? nutritionStreak + 1 : 1) : 0
            if nutritionStreak > 0 && nutritionStreak % 7 == 0 {
                result.append(TimelineMilestone(id: "nutrition-\(dateKey(day.date, calendar: calendar))", date: day.date, kind: "nutrition",
                    title: L10n.text("Nutrition target streak"), detail: L10n.text("Both current nutrition targets met on %@ consecutive logged days.", String(nutritionStreak))))
            }
            previousDay = day.date
        }
        // Metadata alone must not manufacture a tracking milestone.
        var source = history; source.milestones = []
        let dates = recordedDates(history: source, calendar: calendar, asOf: asOf)
        if let first = dates.first, let anniversary = calendar.date(byAdding: .month, value: 1, to: first),
           let day = dates.first(where: { $0 >= anniversary }) {
            result.append(TimelineMilestone(id: "tracking-first-month", date: day, kind: "tracking",
                title: L10n.text("First month of tracking"), detail: L10n.text("Your archive now spans at least one calendar month. Missing days are not counted as logged days.")))
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
