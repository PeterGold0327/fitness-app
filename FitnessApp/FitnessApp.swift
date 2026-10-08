import SwiftUI
import SwiftData

@MainActor final class ApplicationRuntime: ObservableObject {
    var container: ModelContainer?
    var store: AppStore?
    var startupError: String?
    init() {
        do {
            let schema = Schema([UserProfile.self, DailyNutrition.self, Meal.self, FoodItem.self,
                                 WeightEntry.self, WorkoutSession.self, ExerciseEntry.self, SleepEntry.self,
                                 BadmintonEntry.self, FoodInventoryItem.self, WeeklySummary.self])
            #if DEBUG
            let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
            #else
            let testing = false
            #endif
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: testing)])
            self.container = container
            self.store = AppStore(context: container.mainContext)
        } catch { startupError = error.localizedDescription }
    }
}

@main struct FitnessApp: App {
    @StateObject private var runtime = ApplicationRuntime()
    @StateObject private var health = HealthService()
    var body: some Scene {
        WindowGroup {
            if let container = runtime.container, let store = runtime.store {
                RootView().environmentObject(store).environmentObject(health).environmentObject(store.foodAnalysisSettings).modelContainer(container)
            } else {
                ContentUnavailableView("Local storage could not open", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(runtime.startupError ?? "Please restart the app. Your data has not been deleted."))
            }
        }
    }
}
