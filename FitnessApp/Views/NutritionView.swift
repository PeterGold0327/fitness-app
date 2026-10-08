import SwiftUI

struct NutritionView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var sheet: AppSheet?
    @State private var selectedDay = Date()
    private var selectedMeals: [Meal] { store.meals.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) } }
    var body: some View {
        List {
            Section("Today") { NutritionTotals(); BreakfastCard(sheet: $sheet) }
            Section {
                Button("What should I eat now?") { sheet = .recommendations }
                Button("Log food") { sheet = .meal(nil) }
                Button("Take or upload food photo") { sheet = .foodPhoto }
            }
            Section("Food log") {
                Button("Today") { selectedDay = store.currentDate }
                DatePicker("Day", selection: $selectedDay, in: ...Date(), displayedComponents: .date)
                if selectedMeals.isEmpty { Text("No meals recorded for this day.").foregroundStyle(.secondary) }
                ForEach(selectedMeals) { meal in
                    Button { sheet = .meal(meal) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meal.name).foregroundStyle(.primary)
                            if let source = FoodAnalysisSource(rawValue: meal.analysisSource), source != .manual && source != .recipe {
                                Text(source.label).font(.caption).foregroundStyle(source == .mock || source == .mockFallback ? .orange : .secondary)
                            }
                            Text("\((meal.calories).wholeText) kcal · \((meal.protein).wholeText) g protein · \(meal.date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { store.deleteMeal(meal) } }
                }
                if !selectedMeals.isEmpty {
                    Text("Day total: \((selectedMeals.reduce(0) { $0 + $1.calories }).wholeText) kcal · \((selectedMeals.reduce(0) { $0 + $1.protein }).wholeText) g protein")
                        .font(.subheadline)
                }
            }
        }.navigationTitle("Nutrition")
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
                    Text("\((store.remainingCalories).wholeText) kcal and \((store.remainingProtein).wholeText) g protein remaining today.")
                    Text("Estimates use typical labels. Grams are edible portions; rice and chicken are weighed cooked. Your existing targets stay unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(store.recommendations) { option in
                    Section(option.name) {
                        Text(option.portionText)
                        Text("≈ \((option.calories).wholeText) kcal · \((option.protein).wholeText) g protein · \((option.carbs).wholeText) g carbs · \((option.fat).wholeText) g fat")
                        Text(option.note).font(.caption).foregroundStyle(.secondary)
                        Button("I ate this — log meal") {
                            guard !saving else { return }; saving = true
                            if store.logOption(option) { dismiss() } else { saving = false }
                        }.disabled(saving)
                    }
                }
                Section { Text("Options prioritize inventory matches, then calorie and protein needs. Portions also consider today's logged or readable Health gym/badminton activity. Weight advice is shown for review.").font(.caption) }
            }.navigationTitle("Eat now")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
