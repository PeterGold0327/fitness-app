import SwiftUI
import Combine
import UIKit
import OSLog

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
    private let navigationLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LeanLog", category: "Navigation")
    var body: some View {
        Group {
            if store.isReady { tabs }
            else {
                ContentUnavailableView {
                    Label(L10n.text("Local logs could not load"), systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? L10n.text("Please retry. Your logs have not been deleted."))
                } actions: { Button(L10n.text("Retry loading")) { store.reload() } }
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
                .tabItem { Label(L10n.text("Home"), systemImage: "house") }
            NavigationStack { NutritionView(sheet: $sheet) }
                .tabItem { Label(L10n.text("Nutrition"), systemImage: "fork.knife") }
            NavigationStack { TrainingView(sheet: $sheet) }
                .tabItem { Label(L10n.text("Training"), systemImage: "dumbbell") }
            progressTab
                .tabItem { Label(L10n.text("Progress"), systemImage: "chart.xyaxis.line") }
            NavigationStack { SettingsView() }
                .tabItem { Label(L10n.text("Settings"), systemImage: "gearshape") }
        }
        .tint(.teal)
    }

    // The actual TabView branch owns the archive entry points. They are not part
    // of a child List's lazy cells or dependent on which analytics sections render.
    private var progressTab: some View {
        NavigationStack {
            ProgressViewScreen(sheet: $sheet)
                .safeAreaInset(edge: .top, spacing: 0) { progressArchiveNavigation }
                .onAppear {
                    navigationLogger.notice("Rendered Progress route: FitnessApp -> RootView.tabs -> RootView.progressTab -> ProgressViewScreen; archive navigation attached by RootView (progress-root-archive-v3).")
                }
        }
    }

    private var progressArchiveNavigation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("Growth Timeline")).font(.headline).padding(.bottom, 4)
            NavigationLink { GrowthTimelineView() } label: {
                progressArchiveLabel(L10n.text("Growth Timeline"), symbol: "calendar")
            }.accessibilityIdentifier("progress.timeline")
            NavigationLink { MilestonesView() } label: {
                progressArchiveLabel(L10n.text("Milestones"), symbol: "flag")
            }.accessibilityIdentifier("progress.milestones")
            NavigationLink { ProgressPhotosView() } label: {
                progressArchiveLabel(L10n.text("Progress Photos"), symbol: "photo.on.rectangle")
            }.accessibilityIdentifier("progress.photos")
            NavigationLink { OnThisDayView() } label: {
                progressArchiveLabel(L10n.text("On This Day"), symbol: "clock.arrow.circlepath")
            }.accessibilityIdentifier("progress.onThisDay")
            NavigationLink { TimelineExportView(selectedDate: store.currentDate, period: .day) } label: {
                progressArchiveLabel(L10n.text("Export Archive"), symbol: "square.and.arrow.down")
            }.accessibilityIdentifier("progress.export")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.archive.navigation")
    }

    private func progressArchiveLabel(_ title: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct MetricRow: View {
    var title: String
    var value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct NutritionTotals: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricRow(title: L10n.text("Calories"), value: L10n.text("%@ / %@ kcal", String(describing: (store.calories).wholeText), String(describing: (store.profile.calorieTarget).wholeText)))
            ProgressView(value: min(store.calories, store.profile.calorieTarget), total: max(1, store.profile.calorieTarget))
            MetricRow(title: L10n.text("Protein"), value: L10n.text("%@ / %@ g", String(describing: (store.protein).wholeText), String(describing: (store.profile.proteinTarget).wholeText)))
            ProgressView(value: min(store.protein, store.profile.proteinTarget), total: max(1, store.profile.proteinTarget))
            Text(L10n.text("Remaining: %@ kcal · %@ g protein", String(describing: (store.remainingCalories).wholeText), String(describing: (store.remainingProtein).wholeText))).font(.subheadline)
            if store.calories > store.profile.calorieTarget {
                Text(L10n.text("%@ kcal above target", String(describing: (store.calories - store.profile.calorieTarget).wholeText))).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}

struct BreakfastCard: View {
    @EnvironmentObject private var store: AppStore
    @Binding var sheet: AppSheet?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("Breakfast · %@", String(describing: L10n.text(store.day.breakfastStatus.capitalized)))).font(.headline)
            if let meal = store.loggedBreakfast {
                Text(meal.analysisSource == "recipe" ? L10n.text(meal.name) : meal.name).font(.subheadline)
                Text(L10n.text("%@ kcal · %@ g protein", String(describing: meal.calories.wholeText), String(describing: meal.protein.wholeText))).foregroundStyle(.secondary)
            } else {
                Text(store.breakfast.portionText).font(.subheadline)
                Text(L10n.text("≈ %@ kcal · %@ g protein", String(describing: store.breakfast.calories.wholeText), String(describing: store.breakfast.protein.wholeText))).foregroundStyle(.secondary)
            }
            if store.day.breakfastStatus == "planned" {
                Text(L10n.text("Planned breakfast is not counted until you mark it eaten.")).font(.caption)
                HStack {
                    Button(L10n.text("Mark eaten")) { store.logOption(store.breakfast, breakfast: true) }.buttonStyle(.borderedProminent)
                    Button(L10n.text("Skip")) { store.skipBreakfast() }.buttonStyle(.bordered)
                }
            } else if store.day.breakfastStatus == "skipped" {
                Button(L10n.text("Restore breakfast")) { store.restoreBreakfast() }.buttonStyle(.bordered)
            } else {
                if let meal = store.loggedBreakfast { Button(L10n.text("Edit eaten breakfast")) { sheet = .meal(meal) }.buttonStyle(.bordered) }
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
                        .accessibilityLabel(L10n.text("Dismiss error"))
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
                Button(L10n.text("Done")) { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }.scrollDismissesKeyboard(.interactively)
    }
}
