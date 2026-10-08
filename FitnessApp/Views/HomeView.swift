import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @Binding var sheet: AppSheet?
    var body: some View {
        List {
            Section(L10n.text("Today")) { NutritionTotals() }
            Section { BreakfastCard(sheet: $sheet) }
            quickActionsSection
            activitySection
            if !health.requestedAccess {
                Section(L10n.text("Apple Health")) {
                    NavigationLink(L10n.text("Connect Apple Health")) { HealthPermissionsView() }
                }
            }
            nextStepSection
        }.navigationTitle(L10n.text("Today"))
        .refreshable { store.reload(); await health.refresh(into: store) }
    }

    private var nextStepSection: some View {
        Section(L10n.text("Next step")) {
            Text(store.trend.advice)
            if let option = store.recommendations.first {
                Text(L10n.text("Try: %@ · %@", String(describing: option.displayName), String(describing: option.portionText))).font(.subheadline)
            }
        }
    }

    private var activitySection: some View {
        Section(L10n.text("Activity & recovery")) {
            MetricRow(title: L10n.text("Gym today"), value: store.manuallyTrainedToday ? L10n.text("Logged") : store.trainedToday ? L10n.text("Apple Health") : L10n.text("Not logged"))
            MetricRow(title: L10n.text("Badminton today"), value: store.manuallyPlayedBadmintonToday ? L10n.text("Logged") : store.badmintonToday ? L10n.text("Apple Health") : L10n.text("Not logged"))
            MetricRow(title: L10n.text("Latest weight"), value: store.weights.last.map { store.weightText($0.kilograms) } ?? L10n.text("—"))
            if let weight = store.weights.last { Text(L10n.text("%@ · %@", String(describing: weight.day.formatted(date: .abbreviated, time: .omitted)), String(describing: L10n.text(weight.source)))).font(.caption).foregroundStyle(.secondary) }
            MetricRow(title: L10n.text("7-day average"), value: store.trend.average.map(store.weightText) ?? L10n.text("—"))
            MetricRow(title: L10n.text("Weight trend"), value: store.trend.label)
            MetricRow(title: L10n.text("Last night's sleep"), value: store.latestSleep.map { L10n.text("%@ h", $0.hours.formatted(.number.precision(.fractionLength(1)))) } ?? L10n.text("No readable data"))
            MetricRow(title: L10n.text("Recent average sleep"), value: store.recentSleepAverage.map { L10n.text("%@ h", $0.formatted(.number.precision(.fractionLength(1)))) } ?? L10n.text("—"))
            MetricRow(title: L10n.text("Steps"), value: health.steps.map { String(($0).wholeText) } ?? L10n.text("—"))
            MetricRow(title: L10n.text("Active calories"), value: health.activeCalories.map { L10n.text("%@ kcal", String(describing: ($0).wholeText)) } ?? L10n.text("—"))
            MetricRow(title: L10n.text("Latest heart rate today"), value: health.heartRate.map { L10n.text("%@ bpm", String(describing: ($0).wholeText)) } ?? L10n.text("—"))
            Text(L10n.text("Weight and sleep may be locally cached from Health. Sleep uses noon-to-noon windows, including naps. Active calories are informational and are not added to your food target."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var quickActionsSection: some View {
        Section(L10n.text("Quick actions")) {
            Button { sheet = .meal(nil) } label: { Label(L10n.text("Log food"), systemImage: "plus.circle") }
            Button { sheet = .foodPhoto } label: { Label(L10n.text("Take food photo"), systemImage: "camera") }
            Button { sheet = .recommendations } label: { Label(L10n.text("What should I eat now?"), systemImage: "fork.knife.circle") }
            Button { sheet = .workout(nil) } label: { Label(L10n.text("Log gym workout"), systemImage: "dumbbell") }
            Button { sheet = .weight(nil) } label: { Label(L10n.text("Log weight"), systemImage: "scalemass") }
            Button { sheet = .badminton } label: { Label(L10n.text("Log badminton"), systemImage: "figure.badminton") }
        }
    }
}
