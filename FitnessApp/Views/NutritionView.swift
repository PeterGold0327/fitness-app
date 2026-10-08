import SwiftUI

struct NutritionView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var sheet: AppSheet?
    @State private var selectedDay = Date()
    private var selectedMeals: [Meal] { store.meals.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) } }
    var body: some View {
        List {
            Section(L10n.text("Today")) { NutritionTotals(); BreakfastCard(sheet: $sheet) }
            Section {
                Button(L10n.text("What should I eat now?")) { sheet = .recommendations }
                Button(L10n.text("Log food")) { sheet = .meal(nil) }
                Button(L10n.text("Take or upload food photo")) { sheet = .foodPhoto }
            }
            Section(L10n.text("Food log")) {
                Button(L10n.text("Today")) { selectedDay = store.currentDate }
                DatePicker(L10n.text("Day"), selection: $selectedDay, in: ...Date(), displayedComponents: .date)
                if selectedMeals.isEmpty { Text(L10n.text("No meals recorded for this day.")).foregroundStyle(.secondary) }
                ForEach(selectedMeals) { meal in
                    Button { sheet = .meal(meal) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meal.analysisSource == "recipe" ? L10n.text(meal.name) : meal.name).foregroundStyle(.primary)
                            if let source = FoodAnalysisSource(rawValue: meal.analysisSource), source != .manual && source != .recipe {
                                Text(source.label).font(.caption).foregroundStyle(source == .mock || source == .mockFallback ? Color.orange : Color.secondary)
                            }
                            Text(L10n.text("%@ kcal · %@ g protein · %@", String(describing: (meal.calories).wholeText), String(describing: (meal.protein).wholeText), String(describing: meal.date.formatted(date: .omitted, time: .shortened))))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button(L10n.text("Delete"), role: .destructive) { store.deleteMeal(meal) } }
                }
                if !selectedMeals.isEmpty {
                    Text(L10n.text("Day total: %@ kcal · %@ g protein", String(describing: (selectedMeals.reduce(0) { $0 + $1.calories }).wholeText), String(describing: (selectedMeals.reduce(0) { $0 + $1.protein }).wholeText)))
                        .font(.subheadline)
                }
            }
        }.navigationTitle(L10n.text("Nutrition"))
            .onChange(of: store.day.day) { oldDay, newDay in
                if Calendar.current.isDate(selectedDay, inSameDayAs: oldDay) { selectedDay = newDay }
            }
    }
}

struct RecommendationsView: View {
    @State private var saving = false
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L10n.text("%@ kcal and %@ g protein remaining today.", String(describing: (store.remainingCalories).wholeText), String(describing: (store.remainingProtein).wholeText)))
                    Text(L10n.text("Estimates use typical labels. Grams are edible portions; rice and chicken are weighed cooked. Your existing targets stay unchanged."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(store.recommendations) { option in
                    Section(option.displayName) {
                        Text(option.portionText)
                        Text(L10n.text("≈ %@ kcal · %@ g protein · %@ g carbs · %@ g fat", String(describing: (option.calories).wholeText), String(describing: (option.protein).wholeText), String(describing: (option.carbs).wholeText), String(describing: (option.fat).wholeText)))
                        Text(option.note).font(.caption).foregroundStyle(.secondary)
                        Button(L10n.text("I ate this — log meal")) {
                            guard !saving else { return }; saving = true
                            if store.logOption(option) { dismiss() } else { saving = false }
                        }.disabled(saving)
                    }
                }
                Section { Text(L10n.text("Options prioritize inventory matches, then calorie and protein needs. Portions also consider today's logged or readable Health gym/badminton activity. Weight advice is shown for review.")).font(.caption) }
            }.navigationTitle(L10n.text("Eat now"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Close")) { dismiss() } } }
        }
    }
}
