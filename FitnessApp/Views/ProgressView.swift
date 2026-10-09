import SwiftUI
import Charts

struct ProgressOverviewView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var sheet: AppSheet?
    private var chartWeights: [WeightEntry] { store.weights.filter { EntryValidation.weight($0.kilograms) && $0.day >= store.startOfRecentDays(28) && $0.day <= Date() } }
    private var averages: [WeightPoint] {
        chartWeights.compactMap { entry in
            let trend = FitnessLogic.weightTrend(store.weightPoints, now: entry.day)
            return trend.average.map { WeightPoint(date: entry.day, kilograms: $0) }
        }
    }
    var body: some View {
        List {
            weightSection
            nutritionSection
            gymProgressSection
            weeklySummarySection
            if !store.summaries.isEmpty {
                Section(L10n.text("Saved summaries")) {
                    ForEach(store.summaries) { summary in
                        DisclosureGroup(summary.generatedAt.formatted(date: .abbreviated, time: .omitted)) { Text(summary.text) }
                    }
                }
            }
            weightHistorySection
        }.navigationTitle(L10n.text("Overview"))
    }

    private var weightHistorySection: some View {
        Section(L10n.text("Weight history")) {
            if store.weights.isEmpty { Text(L10n.text("No weigh-ins yet.")).foregroundStyle(.secondary) }
            ForEach(store.weights.reversed()) { entry in
                Button { sheet = .weight(entry) } label: {
                    MetricRow(title: entry.day.formatted(date: .abbreviated, time: .omitted), value: L10n.text("%@ · %@", String(describing: store.weightText(entry.kilograms)), String(describing: L10n.text(entry.source))))
                }
                .swipeActions { Button(L10n.text("Delete"), role: .destructive) { store.deleteWeight(entry) } }
            }
        }
    }

    private var weeklySummarySection: some View {
        Section(L10n.text("Weekly summary")) {
            Text(store.weeklySummaryText)
            Button(L10n.text("Save this weekly summary")) { store.saveWeeklySummary() }
        }
    }

    private var gymProgressSection: some View {
        Section(L10n.text("Gym progress")) {
            if store.recentExerciseNames.isEmpty { Text(L10n.text("Log gym exercises this week to see progress and next-week advice.")).foregroundStyle(.secondary) }
            ForEach(store.recentExerciseNames, id: \.self) { name in
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    Text(store.exerciseProgress(name: name)).font(.subheadline)
                    Text(store.exerciseAdvice(name: name)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var nutritionSection: some View {
        Section(L10n.text("Nutrition adherence · last 7 days")) {
            ForEach(0..<7, id: \.self) { offset in
                let date = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: .now))!
                let meals = store.meals.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                    if meals.isEmpty { Text(L10n.text("Not logged")).foregroundStyle(.secondary) }
                    else {
                        let calories = meals.reduce(0) { $0 + $1.calories }
                        let protein = meals.reduce(0) { $0 + $1.protein }
                        Text(L10n.text("%@ / %@ kcal · %@ / %@ g protein", String(describing: (calories).wholeText), String(describing: (store.profile.calorieTarget).wholeText), String(describing: (protein).wholeText), String(describing: (store.profile.proteinTarget).wholeText)))
                        ProgressView(value: min(calories, store.profile.calorieTarget), total: max(1, store.profile.calorieTarget))
                    }
                }.font(.subheadline)
            }
            Text(L10n.text("Compared with current targets. A partially logged day is not a complete intake record.")).font(.caption)
        }
    }

    private var weightSection: some View {
        Section(L10n.text("Body weight · last 4 weeks")) {
            Button(L10n.text("Log weight")) { sheet = .weight(nil) }
            if chartWeights.isEmpty { Text(L10n.text("Log daily weigh-ins to see your chart.")).foregroundStyle(.secondary) }
            else {
                Chart {
                    ForEach(chartWeights) { entry in
                        PointMark(x: .value(L10n.text("Date"), entry.day), y: .value(L10n.text("Weight"), store.displayedWeight(entry.kilograms)))
                            .foregroundStyle(by: .value(L10n.text("Series"), L10n.text("Daily weigh-in")))
                    }
                    ForEach(averages, id: \.date) { point in
                        LineMark(x: .value(L10n.text("Date"), point.date), y: .value(L10n.text("Weight"), store.displayedWeight(point.kilograms)))
                            .foregroundStyle(by: .value(L10n.text("Series"), L10n.text("7-day average")))
                    }
                }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 220)
                    .accessibilityLabel(L10n.text("Daily weight and seven-day moving average, in %@", String(describing: store.profile.usesPounds ? L10n.text("pounds") : L10n.text("kilograms"))))
            }
            MetricRow(title: L10n.text("7-day average"), value: store.trend.average.map(store.weightText) ?? L10n.text("—"))
            TrendRow(title: L10n.text("2-week comparison"), trend: store.trend)
            TrendRow(title: L10n.text("4-week comparison"), trend: FitnessLogic.weightTrend(store.weightPoints, now: store.currentDate, weeks: 4))
            Text(store.trend.advice).font(.subheadline)
            Text(L10n.text("Trends compare the most recent 7-day average with the first week in the selected window. At least 4 weigh-ins are required in each comparison week.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TrendRow: View {
    @EnvironmentObject private var store: AppStore
    var title: String
    var trend: WeightTrend
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MetricRow(title: title, value: trend.label)
            if let gain = trend.weeklyGain { Text(L10n.text("%@ %@/week", String(format: "%+.2f", locale: Locale.current, store.displayedWeight(gain)), store.profile.usesPounds ? L10n.text("lb") : L10n.text("kg"))).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct WeightEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var existing: WeightEntry? = nil
    @State private var weight = 63.0
    @State private var date = Date()
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L10n.text("Day"), selection: $date, in: ...Date(), displayedComponents: .date).disabled(existing != nil)
                NumberField(title: L10n.text("Weight (%@)", String(describing: store.profile.usesPounds ? L10n.text("lb") : L10n.text("kg"))), value: $weight)
                Text(L10n.text("One weigh-in per day. Saving replaces that day's value. Manual entries take priority over Apple Health imports.")).font(.caption)
            }.navigationTitle(L10n.text("Log weight")).keyboardDoneButton()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("Save")) { if store.logWeight(kilograms: store.kilograms(from: weight), date: date) { dismiss() } }
                            .disabled(!EntryValidation.weight(store.kilograms(from: weight)))
                    }
                }
                .task {
                    guard !loaded else { return }; loaded = true
                    weight = store.displayedWeight(existing?.kilograms ?? store.weights.last?.kilograms ?? store.profile.startingWeightKG)
                    date = existing?.day ?? .now
                }
        }
    }
}
