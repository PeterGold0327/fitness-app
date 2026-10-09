import XCTest
import Foundation
#if SWIFT_PACKAGE
@testable import FitnessCore
#else
@testable import LeanLog
#endif

final class GrowthTimelineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2; value.minimumDaysInFirstWeek = 4
        return value
    }
    private func date(_ day: Int, month: Int = 10, year: Int = 2026, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func meal(_ date: Date, calories: Double = 2700, protein: Double = 130, name: String = "午餐") -> TimelineMeal {
        TimelineMeal(id: UUID(), date: date, name: name, category: .lunch, calories: calories, protein: protein, carbs: 200, fat: 60)
    }
    private func exercise(_ weight: Double = 40, reps: Int = 10, sets: Int = 3, name: String = "Squat") -> TimelineExercise {
        TimelineExercise(name: name, weight: weight, sets: sets, reps: reps, rpe: 7, notes: "Controlled form")
    }
    private func workout(_ date: Date, weight: Double = 40, sets: Int = 3) -> TimelineWorkout {
        TimelineWorkout(id: UUID(), date: date, name: "Legs", exercises: [exercise(weight, sets: sets)])
    }
    private func photo(_ date: Date, angle: ProgressPhotoAngle = .front, id: UUID = UUID()) -> TimelinePhoto {
        TimelinePhoto(id: id, date: date, angle: angle, notes: "Private", data: Data([0xff, 0xd8, 0xff, 0xd9]))
    }
    func testDailyAggregationUsesAllCanonicalFieldsAndExcludesFutureRecords() {
        var history = TimelineHistory()
        history.meals = [meal(date(9), calories: 700, protein: 40), meal(date(9, hour: 19), calories: 500, protein: 30), meal(date(10))]
        history.weights = [TimelineWeight(date: date(9, hour: 0), kilograms: 63.4)]
        history.sleep = [TimelineSleep(date: date(9, hour: 0), hours: 7.4)]
        history.workouts = [workout(date(9))]
        history.badminton = [date(9), date(10)]
        history.photos = [photo(date(9))]
        let day = GrowthTimeline.day(date(9), history: history, calendar: calendar, asOf: date(9, hour: 23))
        XCTAssertEqual(day.calories, 1200); XCTAssertEqual(day.protein, 70)
        XCTAssertEqual(day.carbs, 400); XCTAssertEqual(day.fat, 120)
        XCTAssertEqual(day.weight, 63.4); XCTAssertEqual(day.sleep, 7.4)
        XCTAssertEqual(day.workouts.count, 1); XCTAssertEqual(day.photos.count, 1); XCTAssertTrue(day.badminton)
        XCTAssertTrue(day.summary.contains(GrowthTimeline.number(1200)))
        XCTAssertEqual(history.meals.count, 3, "Aggregation must not mutate source history")
        XCTAssertFalse(GrowthTimeline.day(date(10), history: history, calendar: calendar, asOf: date(9, hour: 23)).hasRecords)
    }
    func testMidnightGroupingUsesSelectedCalendarTimezone() {
        var brisbane = calendar; brisbane.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        var history = TimelineHistory()
        history.meals = [meal(date(8, hour: 13)), meal(date(8, hour: 14))]
        let days = GrowthTimeline.days(history: history, interval: nil, calendar: brisbane, asOf: date(10))
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(GrowthTimeline.dateKey(days[0].date, calendar: brisbane), "2026-10-08")
        XCTAssertEqual(GrowthTimeline.dateKey(days[1].date, calendar: brisbane), "2026-10-09")
        XCTAssertEqual(days.map { $0.meals.count }, [1, 1])
    }
    func testHalfOpenPeriodBoundariesDoNotDuplicateMeals() {
        let start = date(9, hour: 0), end = date(10, hour: 0)
        var history = TimelineHistory(); history.meals = [meal(start), meal(end)]
        let days = GrowthTimeline.days(history: history, interval: DateInterval(start: start, end: end), calendar: calendar, asOf: date(11))
        XCTAssertEqual(days.count, 1); XCTAssertEqual(days[0].meals.count, 1)
    }
    func testDaylightSavingDayAndWeekUseCalendarArithmetic() {
        var la = calendar; la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let spring = la.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let interval = TimelinePeriod.day.interval(containing: spring, calendar: la)
        XCTAssertEqual(interval.duration, 23 * 3600)
        var history = TimelineHistory(); history.meals = [meal(spring)]
        let summary = GrowthTimeline.summary(history: history, interval: TimelinePeriod.week.interval(containing: spring, calendar: la), calendar: la, asOf: spring)
        XCTAssertEqual(summary.calendarDays, 7); XCTAssertEqual(summary.nutritionDays, 1)
    }
    func testWeeklySummaryWeightsNutritionCoverageSleepAndAdherence() {
        var history = TimelineHistory()
        history.weights = [TimelineWeight(date: date(5), kilograms: 63), TimelineWeight(date: date(9), kilograms: 64)]
        history.meals = [meal(date(5)), meal(date(9), calories: 2000, protein: 90)]
        history.sleep = [TimelineSleep(date: date(5), hours: 8), TimelineSleep(date: date(9), hours: 6)]
        history.workouts = [workout(date(5)), workout(date(9))]
        history.badminton = [date(9), date(9)]
        let summary = GrowthTimeline.summary(history: history, interval: TimelinePeriod.week.interval(containing: date(9), calendar: calendar), calendar: calendar, asOf: date(12))
        XCTAssertEqual(summary.calendarDays, 7); XCTAssertEqual(summary.nutritionDays, 2)
        XCTAssertEqual(summary.startingWeight, 63); XCTAssertEqual(summary.endingWeight, 64); XCTAssertEqual(summary.averageWeight, 63.5)
        XCTAssertEqual(summary.averageCalories, 2350); XCTAssertEqual(summary.averageProtein, 110)
        XCTAssertEqual(summary.gymSessions, 2); XCTAssertEqual(summary.badmintonDays, 1)
        XCTAssertEqual(summary.averageSleep, 7); XCTAssertEqual(summary.sleepNights, 2)
        XCTAssertEqual(summary.calorieAdherentDays, 1); XCTAssertEqual(summary.proteinAdherentDays, 1); XCTAssertEqual(summary.jointlyAdherentDays, 1)
    }
    func testMonthlyComparisonPreservesMissingDataAndTrainingFrequency() {
        var history = TimelineHistory(); history.meals = [meal(date(1, month: 9)), meal(date(1), calories: 2800)]
        history.weights = [TimelineWeight(date: date(1, month: 9), kilograms: 63), TimelineWeight(date: date(1), kilograms: 64)]
        history.workouts = [workout(date(1)), workout(date(2))]
        let current = GrowthTimeline.summary(history: history, interval: TimelinePeriod.month.interval(containing: date(9), calendar: calendar), calendar: calendar, asOf: date(31))
        let previous = GrowthTimeline.summary(history: history, interval: TimelinePeriod.month.interval(containing: date(1, month: 9), calendar: calendar), calendar: calendar, asOf: date(31))
        XCTAssertEqual(current.calendarDays, 31); XCTAssertEqual(previous.calendarDays, 30)
        XCTAssertEqual(current.gymSessions, 2); XCTAssertTrue(current.comparison(with: previous).contains("+1.0"))
        XCTAssertNil(previous.averageSleep)
        XCTAssertTrue(current.comparison(with: previous).contains(L10n.text("—")))
    }
    func testYearAndEmptyFuturePeriods() {
        var history = TimelineHistory(); history.meals = [meal(date(1, year: 2025)), meal(date(1)), meal(date(1, year: 2027))]
        let year = GrowthTimeline.summary(history: history, interval: TimelinePeriod.year.interval(containing: date(9), calendar: calendar), calendar: calendar, asOf: date(31, month: 12))
        XCTAssertEqual(year.days.count, 1); XCTAssertEqual(year.calendarDays, 365)
        let future = GrowthTimeline.summary(history: history, interval: TimelinePeriod.year.interval(containing: date(1, year: 2027), calendar: calendar), calendar: calendar, asOf: date(9))
        XCTAssertTrue(future.days.isEmpty); XCTAssertEqual(future.calendarDays, 0)
        XCTAssertNil(future.averageCalories); XCTAssertEqual(future.text, L10n.text("No records in this period."))
    }
    func testSevenDayMovingAverageIncludesPriorPeriodButExcludesOlderFutureWeights() {
        var history = TimelineHistory()
        history.weights = [TimelineWeight(date: date(24, month: 9), kilograms: 90), TimelineWeight(date: date(25, month: 9), kilograms: 62),
                           TimelineWeight(date: date(1), kilograms: 64), TimelineWeight(date: date(2), kilograms: 80)]
        let day = GrowthTimeline.day(date(1), history: history, calendar: calendar, asOf: date(1, hour: 23))
        XCTAssertEqual(day.weightAverage, 63); XCTAssertEqual(day.weightSampleCount, 2)
        let days = GrowthTimeline.days(history: history, interval: TimelinePeriod.month.interval(containing: date(1), calendar: calendar), calendar: calendar, asOf: date(1, hour: 23))
        XCTAssertEqual(days[0].weightAverage, day.weightAverage)
    }
    func testExerciseProgressionNormalizesNamesAndExcludesUncompletedRows() {
        var history = TimelineHistory()
        history.workouts = [workout(date(1)), TimelineWorkout(id: UUID(), date: date(5), name: "Gym", exercises: [exercise(50, name: "squat"), exercise(100, sets: 0)])]
        let summary = GrowthTimeline.summary(history: history, interval: TimelinePeriod.month.interval(containing: date(9), calendar: calendar), calendar: calendar, asOf: date(9))
        XCTAssertEqual(summary.exercises.count, 1)
        XCTAssertEqual(summary.exercises[0].first.weight, 40); XCTAssertEqual(summary.exercises[0].latest.weight, 50)
        XCTAssertEqual(summary.exercises[0].best.weight, 50)
    }
    func testWeightMilestonesAreUniqueAcrossFluctuationsAndSupportEitherDirection() {
        var history = TimelineHistory()
        history.weights = [TimelineWeight(date: date(1), kilograms: 63.4), TimelineWeight(date: date(2), kilograms: 64.2),
                           TimelineWeight(date: date(3), kilograms: 63.5), TimelineWeight(date: date(4), kilograms: 64.3), TimelineWeight(date: date(5), kilograms: 62.9)]
        let result = GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(9))
        XCTAssertEqual(result.filter { $0.id == "weight-up-64" }.count, 1)
        XCTAssertEqual(result.filter { $0.id == "weight-down-63" }.count, 1)
        XCTAssertEqual(result.first { $0.id == "weight-up-64" }?.date, date(2))
    }
    func testExerciseMilestonesUseSessionBestAndNotSetsOrFirstBaseline() {
        var history = TimelineHistory()
        history.workouts = [workout(date(1)), workout(date(2), sets: 5), workout(date(3), weight: 50), workout(date(4), weight: 100, sets: 0)]
        let result = GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(9)).filter { $0.kind == "exercise" }
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].date, date(3))
        XCTAssertTrue(result[0].detail.contains("50"))
    }
    func testTrainingMilestoneRequiresFourConsecutiveCalendarWeeks() {
        var history = TimelineHistory()
        history.workouts = [workout(date(5)), workout(date(12)), workout(date(19)), workout(date(26))]
        XCTAssertEqual(GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(31)).filter { $0.kind == "training" }.count, 1)
        history.workouts.remove(at: 1)
        XCTAssertFalse(GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(31)).contains { $0.kind == "training" })
    }
    func testNutritionStreakRequiresSevenCompletedLoggedDaysAndBreaksOnGaps() {
        var history = TimelineHistory(); history.meals = (1...7).map { meal(date($0)) }
        XCTAssertFalse(GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(7)).contains { $0.kind == "nutrition" })
        XCTAssertEqual(GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(8)).filter { $0.kind == "nutrition" }.count, 1)
        history.meals.remove(at: 3)
        XCTAssertFalse(GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(9)).contains { $0.kind == "nutrition" })
        history.meals = (1...7).map { meal(date($0), calories: $0 == 4 ? 1500 : 2700) }
        XCTAssertFalse(GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(9)).contains { $0.kind == "nutrition" })
    }
    func testFirstMonthMilestoneNeedsActualTrackingAcrossCalendarMonth() {
        var history = TimelineHistory(); history.meals = [meal(date(1, month: 9)), meal(date(1))]
        XCTAssertTrue(GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(9)).contains { $0.id == "tracking-first-month" })
        history.meals.removeLast()
        XCTAssertFalse(GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(9)).contains { $0.id == "tracking-first-month" })
        history.meals = []; history.milestones = [TimelineMilestone(id: "manual", date: date(1, month: 9), kind: "manual", title: "Note", detail: "")]
        XCTAssertTrue(GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(9)).isEmpty)
    }
    func testMilestoneKeysAreStableAndCorrectionsRemoveInvalidAchievements() {
        var history = TimelineHistory(); history.workouts = [workout(date(1)), workout(date(3), weight: 50)]
        let first = GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(9))
        let again = GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(9))
        XCTAssertEqual(first.map(\.id), again.map(\.id))
        history.workouts[1].exercises[0].weight = 30
        XCTAssertFalse(GrowthTimeline.automaticMilestones(history: history, calendar: calendar, asOf: date(9)).contains { $0.kind == "exercise" })
    }
    func testManualMilestoneAppearsWithoutDuplicatingOtherRecords() {
        var history = TimelineHistory()
        history.milestones = [TimelineMilestone(id: "manual", date: date(9), kind: "manual", title: "First tournament", detail: "Personal note")]
        let day = GrowthTimeline.day(date(9), history: history, calendar: calendar, asOf: date(10))
        XCTAssertTrue(day.hasRecords); XCTAssertEqual(day.milestones.count, 1)
        XCTAssertTrue(day.workouts.isEmpty); XCTAssertTrue(day.meals.isEmpty); XCTAssertNil(day.weight)
    }
    func testPhotoComparisonsMatchAngleAndRequestedCalendarPeriods() {
        let old = photo(date(10, month: 7)), week = photo(date(9, month: 9)), latest = photo(date(9))
        let wrongAngle = photo(date(9), angle: .back)
        let photos = [old, week, latest, wrongAngle]
        let months = GrowthTimeline.photoComparison(photos, angle: .front, monthsAgo: 3, asOf: date(9), calendar: calendar)
        XCTAssertEqual(months?.earlier.id, old.id); XCTAssertEqual(months?.later.id, latest.id)
        let weeks = GrowthTimeline.photoComparison(photos, angle: .front, weeksAgo: 4, asOf: date(9), calendar: calendar)
        XCTAssertEqual(weeks?.earlier.id, week.id)
        let lifetime = GrowthTimeline.photoComparison(photos, angle: .front, asOf: date(9), calendar: calendar)
        XCTAssertEqual(lifetime?.earlier.id, old.id)
        XCTAssertNil(GrowthTimeline.photoComparison(photos, angle: .side, asOf: date(9), calendar: calendar))
    }
    func testMissingPhotoPeriodsDoNotSubstituteDistantOrFuturePhotos() {
        let photos = [photo(date(1, month: 1)), photo(date(9)), photo(date(10))]
        XCTAssertNil(GrowthTimeline.photoComparison(photos, angle: .front, weeksAgo: 4, asOf: date(9), calendar: calendar))
        XCTAssertNil(GrowthTimeline.photoComparison([photos[0]], angle: .front, asOf: date(9), calendar: calendar))
        XCTAssertEqual(GrowthTimeline.photoComparison(photos, angle: .front, asOf: date(9), calendar: calendar)?.later.id, photos[1].id)
    }
    func testOnThisDayUsesExactMonthDayAndMultipleEarlierYears() {
        var history = TimelineHistory()
        history.meals = [meal(date(9, year: 2024)), meal(date(9, year: 2025)), meal(date(8, year: 2025)), meal(date(9))]
        let result = GrowthTimeline.onThisDay(history: history, date: date(9), calendar: calendar)
        XCTAssertEqual(result.count, 2); XCTAssertEqual(calendar.component(.year, from: result[0].date), 2025)
        XCTAssertTrue(GrowthTimeline.onThisDay(history: history, date: date(10), calendar: calendar).isEmpty)
        history.meals = [meal(date(29, month: 2, year: 2024)), meal(date(28, month: 2, year: 2025))]
        XCTAssertEqual(GrowthTimeline.onThisDay(history: history, date: date(29, month: 2, year: 2028), calendar: calendar).count, 1)
    }
    private func archiveFixture() -> TimelineHistory {
        var history = TimelineHistory()
        var lunch = meal(date(9), calories: 700, protein: 40, name: "红烧牛腩")
        lunch.photo = Data([1, 2, 3, 4])
        lunch.foods = [TimelineFood(name: "Corrected rice", grams: 150, calories: 195, protein: 4, carbs: 42, fat: 0.5, confidence: 0.8, notes: "Cooked")]
        history.meals = [lunch]; history.workouts = [workout(date(9))]
        history.weights = [TimelineWeight(date: date(9), kilograms: 63.4)]; history.sleep = [TimelineSleep(date: date(9), hours: 7.4)]
        history.photos = [photo(date(9), angle: .side)]; history.badminton = [date(9)]
        return history
    }
    func testMarkdownContainsDailyFieldsCorrectedFoodsAndExistingPhotoBytes() {
        let history = archiveFixture()
        let archive = TimelineMarkdown.generate(history: history, interval: nil, calendar: calendar, asOf: date(10))
        for value in ["# 2026-10-09", "63.4", "7.4", "红烧牛腩", "Corrected rice", "195.0", "40.0", "Controlled form", "RPE 7.0"] { XCTAssertTrue(archive.markdown.contains(value), value) }
        XCTAssertEqual(archive.photos.count, 2)
        let mealPath = "photos/2026-10-09-meal-\(history.meals[0].id.uuidString.lowercased()).jpg"
        XCTAssertEqual(archive.photos[mealPath], history.meals[0].photo)
        for path in archive.photos.keys { XCTAssertTrue(archive.markdown.contains("](\(path))")) }
        XCTAssertEqual(archive.files["archive.md"], Data(archive.markdown.utf8))
    }
    func testMarkdownPeriodBoundariesAndEntireHistory() {
        var history = archiveFixture(); history.meals.append(meal(date(1, month: 9))); history.meals.append(meal(date(1, year: 2027)))
        for period in TimelinePeriod.allCases {
            let interval = period.interval(containing: date(9), calendar: calendar)
            let archive = TimelineMarkdown.generate(history: history, interval: interval, calendar: calendar, asOf: date(10))
            XCTAssertTrue(archive.markdown.contains("# 2026-10-09"))
            XCTAssertFalse(archive.markdown.contains("# 2027-10-01"))
            if period != .year { XCTAssertFalse(archive.markdown.contains("# 2026-09-01")) }
        }
        let all = TimelineMarkdown.generate(history: history, interval: nil, calendar: calendar, asOf: date(10))
        XCTAssertTrue(all.markdown.contains("# 2026-09-01")); XCTAssertFalse(all.markdown.contains("# 2027-10-01"))
    }
    func testMarkdownEscapesUserContentAndFilenamesNeverUseMealNames() {
        var history = archiveFixture(); history.meals[0].name = "../../secret\n# heading [link](https://example.com)"
        let archive = TimelineMarkdown.generate(history: history, interval: nil, calendar: calendar, asOf: date(10))
        XCTAssertFalse(archive.markdown.contains("\n# heading")); XCTAssertTrue(archive.markdown.contains("\\[link\\]"))
        XCTAssertFalse(archive.photos.keys.contains { $0.contains("..") || $0.contains("secret") })
        let sameDaySecondMeal = history.meals[0]
        history.meals.append(TimelineMeal(id: UUID(), date: sameDaySecondMeal.date, name: sameDaySecondMeal.name, category: .lunch,
                                         calories: 1, protein: 1, carbs: 1, fat: 1, photo: Data([5])))
        XCTAssertEqual(TimelineMarkdown.generate(history: history, interval: nil, calendar: calendar, asOf: date(10)).photos.count, 3)
    }
    func testEmptyHistoricalPeriodsHaveNoInventedTotalsOrPhotoReferences() {
        let history = TimelineHistory()
        for period in TimelinePeriod.allCases {
            let interval = period.interval(containing: date(9), calendar: calendar)
            let summary = GrowthTimeline.summary(history: history, interval: interval, calendar: calendar, asOf: date(10))
            XCTAssertTrue(summary.days.isEmpty); XCTAssertNil(summary.averageWeight); XCTAssertNil(summary.averageCalories); XCTAssertNil(summary.averageSleep)
            let archive = TimelineMarkdown.generate(history: history, interval: interval, calendar: calendar, asOf: date(10))
            XCTAssertTrue(archive.photos.isEmpty); XCTAssertFalse(archive.markdown.contains("!["))
            XCTAssertTrue(archive.markdown.contains(L10n.text("No records in this period.")))
        }
    }
    func testZIPExportFixtureAndUnsafePathsRejected() throws {
        let archive = TimelineMarkdown.generate(history: archiveFixture(), interval: nil, calendar: calendar, asOf: date(10))
        let zipped = try archive.zipData()
        XCTAssertEqual(zipped.prefix(4), Data([0x50, 0x4b, 0x03, 0x04]))
        XCTAssertThrowsError(try TimelineZIP.encode(["../escape.jpg": Data()]))
        XCTAssertThrowsError(try TimelineZIP.encode(["/absolute": Data()]))
        // The validation command opens this fixture with Python's independent ZIP reader,
        // checks every CRC, resolves Markdown references and compares original bytes.
        if let path = ProcessInfo.processInfo.environment["TIMELINE_TEST_ARCHIVE_PATH"] {
            try zipped.write(to: URL(fileURLWithPath: path))
        }
    }
    func testMealCategoryInferenceAndExplicitBreakfastFlag() {
        XCTAssertEqual(TimelineMealCategory.infer(date: date(9, hour: 8), isBreakfast: false, calendar: calendar), .breakfast)
        XCTAssertEqual(TimelineMealCategory.infer(date: date(9, hour: 12), isBreakfast: false, calendar: calendar), .lunch)
        XCTAssertEqual(TimelineMealCategory.infer(date: date(9, hour: 18), isBreakfast: false, calendar: calendar), .dinner)
        XCTAssertEqual(TimelineMealCategory.infer(date: date(9, hour: 16), isBreakfast: false, calendar: calendar), .snack)
        XCTAssertEqual(TimelineMealCategory.infer(date: date(9, hour: 18), isBreakfast: true, calendar: calendar), .breakfast)
    }
    func testMonthlyExerciseComparisonMatchesSameExerciseAndShowsBothBests() {
        var history = TimelineHistory(); history.workouts = [workout(date(1, month: 9)), workout(date(1), weight: 50)]
        let prior = GrowthTimeline.summary(history: history, interval: TimelinePeriod.month.interval(containing: date(1, month: 9), calendar: calendar), calendar: calendar, asOf: date(9))
        let current = GrowthTimeline.summary(history: history, interval: TimelinePeriod.month.interval(containing: date(9), calendar: calendar), calendar: calendar, asOf: date(9))
        let comparisons = current.exerciseComparisons(with: prior)
        XCTAssertEqual(comparisons.count, 1); XCTAssertTrue(comparisons[0].contains("40")); XCTAssertTrue(comparisons[0].contains("50"))
    }
    func testBulkAggregationMatchesIndividualDaysAcrossSparseHistory() {
        var history = TimelineHistory()
        for offset in stride(from: 0, through: 40, by: 2) {
            let day = calendar.date(byAdding: .day, value: offset, to: date(1, month: 8))!
            history.meals.append(meal(day, calories: Double(2000 + offset)))
            history.weights.append(TimelineWeight(date: day, kilograms: 63 + Double(offset) / 100))
        }
        let grouped = GrowthTimeline.days(history: history, interval: nil, calendar: calendar, asOf: date(9))
        for day in grouped {
            let single = GrowthTimeline.day(day.date, history: history, calendar: calendar, asOf: date(9))
            XCTAssertEqual(day.calories, single.calories); XCTAssertEqual(day.weightAverage, single.weightAverage)
            XCTAssertEqual(day.weightSampleCount, single.weightSampleCount)
        }
    }
    func testCancelledArchiveExportStopsBeforeProducingZIP() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TimelineZIP.encode(["archive.md": Data("Private".utf8)])
        }
        do { _ = try await task.value; XCTFail("Cancelled export must not produce an archive") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

}
