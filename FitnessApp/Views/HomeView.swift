import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @EnvironmentObject private var library: PersonalLibrary
    @Binding var sheet: AppSheet?
    private var input: DailyCoachInput { store.coachInput(activeCalories: health.activeCalories, usualActiveCalories: health.usualActiveCalories) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Hello, %@", store.profile.name)).font(.largeTitle.bold())
                    Text(store.currentDate.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
                RecommendationCard(actions: DailyCoach.actions(input))
                quickActions
                yesterdayCard
                sleepCard
                SummaryCard(title: L10n.text("Today's Targets"), symbol: "target") {
                    NutritionTotals()
                    if let goal = library.state.goalWeightKG { MetricRow(title: L10n.text("Goal weight"), value: store.weightText(goal)) }
                    Picker(L10n.text("Today's planned workout"), selection: planned) {
                        Text(L10n.text("Not selected")).tag(TrainingSplit?.none)
                        ForEach(TrainingSplit.allCases) { Text(L10n.text($0.title)).tag(Optional($0)) }
                    }
                }
                SummaryCard(title: L10n.text("Today"), symbol: "figure.walk") {
                    MetricRow(title: L10n.text("Gym today"), value: store.trainedToday ? L10n.text("Recorded") : L10n.text("Not logged"))
                    MetricRow(title: L10n.text("Badminton today"), value: store.badmintonToday ? L10n.text("Recorded") : L10n.text("Not logged"))
                    MetricRow(title: L10n.text("Steps"), value: health.steps?.wholeText ?? L10n.text("No readable data"))
                    MetricRow(title: L10n.text("Active calories"), value: health.activeCalories.map { L10n.text("%@ kcal", $0.wholeText) } ?? L10n.text("No readable data"))
                    MetricRow(title: L10n.text("Latest weight"), value: store.weights.last.map { store.weightText($0.kilograms) } ?? L10n.text("—"))
                    if let weight = store.weights.last { Text(weight.day.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                    if !health.requestedAccess { NavigationLink(L10n.text("Connect Apple Health")) { HealthPermissionsView() } }
                }
                SummaryCard(title: L10n.text("Breakfast"), symbol: "sunrise") { BreakfastCard(sheet: $sheet) }
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("Today")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L10n.text("Log food")) { sheet = .meal(nil) }
                    Button(L10n.text("What should I eat now?")) { sheet = .recommendations }
                    Button(L10n.text("Log gym workout")) { sheet = .workout(nil) }
                    Button(L10n.text("Log weight")) { sheet = .weight(nil) }
                    Button(L10n.text("Log badminton")) { sheet = .badminton }
                } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel(L10n.text("More logging options")).accessibilityIdentifier("home.moreLogging")
            }
        }
        .refreshable { store.reload(); await health.refresh(into: store) }
    }
    private var planned: Binding<TrainingSplit?> {
        Binding(get: { library.planned(on: store.currentDate) }, set: { library.plan($0, date: store.currentDate) })
    }
    private var quickActions: some View {
        VStack(spacing: 10) {
            Button { sheet = .foodPhoto } label: { Label(L10n.text("Take food photo"), systemImage: "camera.fill").frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            HStack {
                NavigationLink { TrainingStartView(sheet: $sheet) } label: { Label(L10n.text("Start training"), systemImage: "dumbbell") }
                Spacer()
                Button(L10n.text("View today's advice")) { sheet = .coach }
            }.buttonStyle(.bordered).controlSize(.large)
        }
    }
    private var yesterdayCard: some View {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: store.currentDate)!
        let meals = store.yesterdayMeals
        let gym = store.workouts.filter { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }.count
        let sports = health.workouts.filter { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
        return SummaryCard(title: L10n.text("Yesterday Summary"), symbol: "checkmark.circle") {
            Text(store.yesterdayNutritionSummary)
            if !meals.isEmpty {
                MetricRow(title: L10n.text("Calories"), value: L10n.text("%@ / %@ kcal", meals.reduce(0) { $0 + $1.calories }.wholeText, store.profile.calorieTarget.wholeText))
                MetricRow(title: L10n.text("Protein"), value: L10n.text("%@ / %@ g", meals.reduce(0) { $0 + $1.protein }.wholeText, store.profile.proteinTarget.wholeText))
            }
            MetricRow(title: L10n.text("Strength training"), value: gym > 0 || sports.contains(where: \.isGym) ? L10n.text("Recorded") : L10n.text("Not logged"))
            if let minutes = sports.filter(\.isBadminton).map(\.minutes).reduce(nil as Double?, { ($0 ?? 0) + $1 }) {
                MetricRow(title: L10n.text("Badminton"), value: L10n.text("%@ min", minutes.wholeText))
            } else if store.badminton.contains(where: { Calendar.current.isDate($0.day, inSameDayAs: yesterday) }) {
                Text(L10n.text("Badminton date recorded; duration unavailable."))
            }
            if let energy = health.yesterdayActiveCalories { MetricRow(title: L10n.text("Active calories"), value: L10n.text("%@ kcal", energy.wholeText)) }
            if let weight = store.weights.first(where: { Calendar.current.isDate($0.day, inSameDayAs: yesterday) }) { MetricRow(title: L10n.text("Weight"), value: store.weightText(weight.kilograms)) }
            Text(L10n.text("Based on logged records and current targets.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var sleepCard: some View {
        SummaryCard(title: L10n.text("Sleep"), symbol: "moon") {
            if let sleep = store.latestSleep {
                Text(L10n.text("%@ h", sleep.hours.formatted(.number.precision(.fractionLength(1))))).font(.title2.bold())
                Text(sleep.hours < 6 ? L10n.text("Short") : sleep.hours >= 8 ? L10n.text("Sufficient") : L10n.text("Normal"))
            } else { Text(L10n.text("No readable sleep data. No recovery assessment is made.")) }
            if let average = store.recentSleepAverage { MetricRow(title: L10n.text("Recent average sleep"), value: L10n.text("%@ h", average.formatted(.number.precision(.fractionLength(1))))) }
            Text(L10n.text("Health sleep includes naps in the noon-to-noon window.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DailyCoachView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    RecommendationCard(actions: DailyCoach.actions(store.coachInput(activeCalories: health.activeCalories, usualActiveCalories: health.usualActiveCalories)))
                    Text(L10n.text("Advice uses recorded meals, training, readable Health activity and sleep. Missing data stays missing; targets never change automatically.")).font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(L10n.text("Today's Recommendation"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Close")) { dismiss() } } }
        }
    }
}
