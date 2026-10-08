import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @Binding var sheet: AppSheet?
    var body: some View {
        List {
            Section("Today") { NutritionTotals() }
            Section { BreakfastCard(sheet: $sheet) }
            Section("Quick actions") {
                Button { sheet = .meal(nil) } label: { Label("Log food", systemImage: "plus.circle") }
                Button { sheet = .foodPhoto } label: { Label("Take food photo", systemImage: "camera") }
                Button { sheet = .recommendations } label: { Label("What should I eat now?", systemImage: "fork.knife.circle") }
                Button { sheet = .workout(nil) } label: { Label("Log gym workout", systemImage: "dumbbell") }
                Button { sheet = .weight(nil) } label: { Label("Log weight", systemImage: "scalemass") }
                Button { sheet = .badminton } label: { Label("Log badminton", systemImage: "figure.badminton") }
            }
            Section("Activity & recovery") {
                MetricRow(title: "Gym today", value: store.manuallyTrainedToday ? "Logged" : store.trainedToday ? "Apple Health" : "Not logged")
                MetricRow(title: "Badminton today", value: store.manuallyPlayedBadmintonToday ? "Logged" : store.badmintonToday ? "Apple Health" : "Not logged")
                MetricRow(title: "Latest weight", value: store.weights.last.map { store.weightText($0.kilograms) } ?? "—")
                if let weight = store.weights.last { Text("\(weight.day.formatted(date: .abbreviated, time: .omitted)) · \(weight.source)").font(.caption).foregroundStyle(.secondary) }
                MetricRow(title: "7-day average", value: store.trend.average.map(store.weightText) ?? "—")
                MetricRow(title: "Weight trend", value: store.trend.label)
                MetricRow(title: "Last night's sleep", value: store.latestSleep.map { String(format: "%.1f h", $0.hours) } ?? "No readable data")
                MetricRow(title: "Recent average sleep", value: store.recentSleepAverage.map { String(format: "%.1f h", $0) } ?? "—")
                MetricRow(title: "Steps", value: health.steps.map { String(($0).wholeText) } ?? "—")
                MetricRow(title: "Active calories", value: health.activeCalories.map { "\(($0).wholeText) kcal" } ?? "—")
                MetricRow(title: "Latest heart rate today", value: health.heartRate.map { "\(($0).wholeText) bpm" } ?? "—")
                Text("Weight and sleep may be locally cached from Health. Sleep uses noon-to-noon windows, including naps. Active calories are informational and are not added to your food target.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !health.requestedAccess {
                Section("Apple Health") {
                    NavigationLink("Connect Apple Health") { HealthPermissionsView() }
                }
            }
            Section("Next step") {
                Text(store.trend.advice)
                if let option = store.recommendations.first {
                    Text("Try: \(option.name) · \(option.portionText)").font(.subheadline)
                }
            }
        }.navigationTitle("Today")
        .refreshable { store.reload(); await health.refresh(into: store) }
    }
}
