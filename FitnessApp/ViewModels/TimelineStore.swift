import Foundation
import SwiftData
import UIKit

extension AppStore {
    var timelineHistory: TimelineHistory { makeTimelineHistory() }

    // Summaries/milestone reconciliation need dates and metadata, not every JPEG.
    // Detail screens restrict lazy external-photo reads to their selected day.
    func makeTimelineHistory(includePhotoData: Bool = true, photoInterval: DateInterval? = nil) -> TimelineHistory {
        func loadPhoto(_ date: Date) -> Bool {
            includePhotoData && (photoInterval.map { GrowthTimeline.contains(date, in: $0) } ?? true)
        }
        var history = TimelineHistory()
        history.calorieTarget = profile.calorieTarget; history.proteinTarget = profile.proteinTarget
        history.meals = meals.map { meal in
            let category = TimelineMealCategory(rawValue: meal.mealCategory) ?? .infer(date: meal.date, isBreakfast: meal.isBreakfast, calendar: .current)
            let foods = meal.foods.sorted { $0.position < $1.position }.map {
                TimelineFood(name: meal.analysisSource == "recipe" ? L10n.text($0.name) : $0.name, grams: $0.grams,
                             calories: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, confidence: $0.confidence, notes: $0.uncertaintyNotes)
            }
            return TimelineMeal(id: meal.id, date: meal.date, name: meal.analysisSource == "recipe" ? L10n.text(meal.name) : meal.name,
                                category: category, calories: meal.calories, protein: meal.protein, carbs: meal.carbs, fat: meal.fat,
                                foods: foods, photo: loadPhoto(meal.date) ? meal.photoData : nil)
        }
        history.weights = weights.map { TimelineWeight(date: $0.day, kilograms: $0.kilograms) }
        history.sleep = sleep.map { TimelineSleep(date: $0.day, hours: $0.hours) }
        history.workouts = workouts.map {
            TimelineWorkout(id: $0.id, date: $0.date, name: $0.name, exercises: $0.exercises.sorted { $0.position < $1.position }.map {
                TimelineExercise(name: $0.name, weight: $0.weightKG, sets: $0.sets, reps: $0.reps, rpe: $0.rpe, notes: $0.notes)
            })
        }
        history.badminton = badminton.map(\.day)
        history.photos = progressPhotos.compactMap {
            guard let angle = ProgressPhotoAngle(rawValue: $0.angle) else { return nil }
            let data: Data
            if loadPhoto($0.date) {
                guard let bytes = $0.photoData else { return nil }
                data = bytes
            } else { data = Data() }
            return TimelinePhoto(id: $0.id, date: $0.date, angle: angle, notes: $0.notes, data: data)
        }
        history.milestones = milestones.map { TimelineMilestone(id: $0.key, date: $0.date, kind: $0.kind, title: $0.title, detail: $0.detail) }
        return history
    }

    func timelinePhotos(angle: ProgressPhotoAngle) -> [TimelinePhoto] {
        progressPhotos.filter { $0.angle == angle.rawValue && $0.date <= currentDate }.compactMap {
            guard let data = $0.photoData else { return nil }
            return TimelinePhoto(id: $0.id, date: $0.date, angle: angle, notes: $0.notes, data: data)
        }
    }

    func reconcileTimelineMilestones() {
        var source = makeTimelineHistory(includePhotoData: false); source.milestones = []
        let detected = GrowthTimeline.automaticMilestones(history: source, calendar: .current, asOf: currentDate)
        let keys = Set(detected.map(\.id))
        for stale in milestones where stale.isAutomatic && !keys.contains(stale.key) { context.delete(stale) }
        var retained = milestones.filter { !$0.isAutomatic || keys.contains($0.key) }
        for rule in detected {
            if let existing = retained.first(where: { $0.key == rule.id && $0.isAutomatic }) {
                if existing.date != rule.date { existing.date = rule.date }
                if existing.title != rule.title { existing.title = rule.title }
                if existing.detail != rule.detail { existing.detail = rule.detail }
            } else {
                let milestone = GrowthMilestone(key: rule.id, date: rule.date, kind: rule.kind, title: rule.title, detail: rule.detail, isAutomatic: true)
                context.insert(milestone); retained.append(milestone)
            }
        }
        milestones = retained.sorted { $0.date > $1.date }
    }

    @discardableResult func logMilestone(title: String, detail: String, date: Date) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReady, !title.isEmpty, title.count <= 200, detail.count <= 4000, date <= currentDate else {
            errorMessage = L10n.text("Enter a milestone title (up to 200 characters), notes (up to 4,000), and a date no later than today.")
            return false
        }
        context.insert(GrowthMilestone(date: date, title: title, detail: detail)); return save()
    }
    func deleteMilestone(_ milestone: GrowthMilestone) {
        guard !milestone.isAutomatic else { return }
        context.delete(milestone); save()
    }
    @discardableResult func logProgressPhoto(data: Data, angle: ProgressPhotoAngle, date: Date, notes: String) -> Bool {
        guard isReady, date <= currentDate, notes.count <= 4000, data.count <= 6 * 1024 * 1024,
              data.starts(with: [0xff, 0xd8, 0xff]), UIImage(data: data) != nil else {
            errorMessage = L10n.text("Choose a valid progress photo, a date no later than today, and notes up to 4,000 characters.")
            return false
        }
        context.insert(ProgressPhoto(date: date, angle: angle.rawValue, notes: notes, photoData: data)); return save()
    }
    func deleteProgressPhoto(_ photo: ProgressPhoto) { context.delete(photo); save() }
}
