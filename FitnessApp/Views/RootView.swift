import SwiftUI
import Combine
import UIKit

// Small shared sheet router; each feature owns its own form and validation.
enum AppSheet: Identifiable {
    case meal(Meal?), foodPhoto, recommendations, weight(WeightEntry?), workout(WorkoutSession?), badminton
    var id: String {
        switch self {
        case .meal(let meal): return "meal-\(meal?.id.uuidString ?? "new")"
        case .foodPhoto: return "photo"
        case .recommendations: return "recommendations"
        case .weight(let entry): return "weight-\(entry.map { String($0.day.timeIntervalSince1970) } ?? "new")"
        case .workout(let workout): return "workout-\(workout?.id.uuidString ?? "new")"
        case .badminton: return "badminton"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: AppSheet?
    var body: some View {
        Group {
            if store.isReady { tabs }
            else {
                ContentUnavailableView {
                    Label("Local logs could not load", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "Please retry. Your logs have not been deleted.")
                } actions: { Button("Retry loading") { store.reload() } }
            }
        }
        .storeErrorBanner()
        .sheet(item: $sheet) { route in
            Group {
                switch route {
                case .meal(let existing): MealEditor(existing: existing)
                case .foodPhoto: MealEditor(startWithCamera: true)
                case .recommendations: RecommendationsView()
                case .weight(let existing): WeightEditor(existing: existing)
                case .workout(let existing): WorkoutEditor(existing: existing)
                case .badminton: BadmintonEditor()
                }
            }.storeErrorBanner()
        }
        .task { store.reload(); await health.refresh(into: store) }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            if !Calendar.current.isDate(store.day.day, inSameDayAs: store.currentDate) {
                store.reload()
                Task { await health.refresh(into: store) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload(); Task { await health.refresh(into: store) } }
        }
    }
    private var tabs: some View {
        TabView {
            NavigationStack { HomeView(sheet: $sheet) }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { NutritionView(sheet: $sheet) }
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
            NavigationStack { TrainingView(sheet: $sheet) }
                .tabItem { Label("Training", systemImage: "dumbbell") }
            NavigationStack { ProgressViewScreen(sheet: $sheet) }
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.teal)
    }
}

struct MetricRow: View {
    var title: String
    var value: String
    var body: some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
    }
}

struct NutritionTotals: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricRow(title: "Calories", value: "\((store.calories).wholeText) / \((store.profile.calorieTarget).wholeText) kcal")
            ProgressView(value: min(store.calories, store.profile.calorieTarget), total: max(1, store.profile.calorieTarget))
            MetricRow(title: "Protein", value: "\((store.protein).wholeText) / \((store.profile.proteinTarget).wholeText) g")
            ProgressView(value: min(store.protein, store.profile.proteinTarget), total: max(1, store.profile.proteinTarget))
            Text("Remaining: \((store.remainingCalories).wholeText) kcal · \((store.remainingProtein).wholeText) g protein").font(.subheadline)
            if store.calories > store.profile.calorieTarget {
                Text("\((store.calories - store.profile.calorieTarget).wholeText) kcal above target").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}

struct BreakfastCard: View {
    @EnvironmentObject private var store: AppStore
    @Binding var sheet: AppSheet?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Breakfast · \(store.day.breakfastStatus.capitalized)").font(.headline)
            if let meal = store.loggedBreakfast {
                Text(meal.name).font(.subheadline)
                Text("\(meal.calories.wholeText) kcal · \(meal.protein.wholeText) g protein").foregroundStyle(.secondary)
            } else {
                Text(store.breakfast.portionText).font(.subheadline)
                Text("≈ \(store.breakfast.calories.wholeText) kcal · \(store.breakfast.protein.wholeText) g protein").foregroundStyle(.secondary)
            }
            if store.day.breakfastStatus == "planned" {
                Text("Planned breakfast is not counted until you mark it eaten.").font(.caption)
                HStack {
                    Button("Mark eaten") { store.logOption(store.breakfast, breakfast: true) }.buttonStyle(.borderedProminent)
                    Button("Skip") { store.skipBreakfast() }.buttonStyle(.bordered)
                }
            } else if store.day.breakfastStatus == "skipped" {
                Button("Restore breakfast") { store.restoreBreakfast() }.buttonStyle(.bordered)
            } else {
                if let meal = store.loggedBreakfast { Button("Edit eaten breakfast") { sheet = .meal(meal) }.buttonStyle(.bordered) }
            }
        }.padding(.vertical, 6)
    }
}

private struct StoreErrorBanner: ViewModifier {
    @EnvironmentObject private var store: AppStore
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top) {
            if let error = store.errorMessage, store.isReady {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).font(.callout)
                    Spacer()
                    Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss error")
                }.padding().background(.regularMaterial)
            }
        }
    }
}

extension View {
    func storeErrorBanner() -> some View { modifier(StoreErrorBanner()) }
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }.scrollDismissesKeyboard(.interactively)
    }
}
