import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @EnvironmentObject private var analysisSettings: FoodAnalysisSettings
    @EnvironmentObject private var library: PersonalLibrary
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        List {
            Section(L10n.text("Personal Goals")) {
                NavigationLink(L10n.text("Profile, targets & breakfast")) { ProfileEditor() }
                NavigationLink(L10n.text("Workout templates")) { WorkoutTemplatesEditor() }
            }
            Section(L10n.text("Apple Health & Data")) {
                NavigationLink(L10n.text("Health permissions & data")) { HealthPermissionsView() }
                NavigationLink(L10n.text("Export Archive")) { TimelineExportView(selectedDate: store.currentDate, period: .day) }
                Text(L10n.text("Watch records appear through Apple Health when readable. This app cannot determine Watch connection or read-denial status.")).font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("Data stays on this iPhone. iCloud sync is not available yet.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("AI Food Recognition")) {
                NavigationLink(L10n.text("Provider & API credentials")) { FoodAnalysisSettingsView() }
                Text(analysisSettings.configuration.mode.label).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("Preferences")) {
                Toggle(L10n.text("Display weight in pounds"), isOn: Binding(get: { store.profile.usesPounds }, set: { store.profile.usesPounds = $0; store.save() }))
                Picker(L10n.text("Appearance"), selection: $appearance) {
                    Text(L10n.text("System")).tag("system")
                    Text(L10n.text("Light")).tag("light")
                    Text(L10n.text("Dark")).tag("dark")
                }
                Button(L10n.text("Language & iPhone settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                NavigationLink(L10n.text("Food inventory (%@)", String(store.inventory.count))) { InventoryView() }
                NavigationLink(L10n.text("Common meals")) { CommonMealsView() }
            }
            if let error = library.error { Section { Text(error).foregroundStyle(.red) } }
        }.calmList().navigationTitle(L10n.text("Settings"))
    }
}

struct ProfileEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @EnvironmentObject private var library: PersonalLibrary
    @State private var goalWeight = 0.0
    @State private var height = 178.0
    @State private var startingWeight = 63.0
    @State private var calories = 2700.0
    @State private var protein = 130.0
    @State private var fat = 70.0
    @State private var yogurt = 200.0
    @State private var banana = 120.0
    @State private var oats = 60.0
    @State private var loaded = false
    private var valid: Bool {
        (goalWeight == 0 || EntryValidation.weight(goalWeight)) && EntryValidation.profile(height: height, startingWeight: startingWeight, calories: calories,
            protein: protein, fat: fat, yogurt: yogurt, banana: banana, oats: oats)
    }
    var body: some View {
        Form {
            profileSection
            targetsSection
            breakfastSection
            if let error = library.error { Section { Text(error).foregroundStyle(.red) } }
            if !valid { Section { Text(L10n.text("Check values: calories 1000–6000, protein 30–300 g, fat 20–200 g, and positive breakfast portions. Protein and fat energy must fit the calorie target.")).foregroundStyle(.red) } }
        }.navigationTitle(L10n.text("Profile & targets")).keyboardDoneButton()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Save")) { save() }.disabled(!valid) } }
            .task { loadProfile() }
    }

    private var carbohydrateTargetText: String {
        let proteinEnergy: Double = protein * 4
        let fatEnergy: Double = fat * 9
        let grams: Double = max(0, (calories - proteinEnergy - fatEnergy) / 4)
        let amount = grams.formatted(.number.precision(.fractionLength(0)))
        return L10n.text("Remaining energy from carbs: about %@ g. Initial target is 2700 kcal, 130 g protein and 70 g fat.", String(describing: amount))
    }

    private var breakfastEstimateText: String {
        let breakfast = FitnessLogic.breakfast(yogurt: yogurt, banana: banana, oats: oats)
        let calories = breakfast.calories.formatted(.number.precision(.fractionLength(0)))
        let protein = breakfast.protein.formatted(.number.precision(.fractionLength(0)))
        return L10n.text("≈ %@ kcal · %@ g protein", String(describing: calories), String(describing: protein))
    }

    private var breakfastSection: some View {
        Section(L10n.text("Automatic daily breakfast")) {
            NumberField(title: L10n.text("Greek yogurt (g)"), value: $yogurt)
            NumberField(title: L10n.text("Banana (g)"), value: $banana)
            NumberField(title: L10n.text("Oats (g)"), value: $oats)
            Text(breakfastEstimateText)
            Text(L10n.text("The default is about 486 kcal and 29 g protein. Changing breakfast portions does not change meals already logged.")).font(.caption)
        }
    }

    private var targetsSection: some View {
        Section(L10n.text("Daily targets")) {
            NumberField(title: L10n.text("Calories (kcal)"), value: $calories)
            NumberField(title: L10n.text("Protein (g)"), value: $protein)
            NumberField(title: L10n.text("Fat (g)"), value: $fat)
            NumberField(title: L10n.text("Goal weight (kg; zero means not set)"), value: $goalWeight)
            Text(carbohydrateTargetText).font(.caption)
            Text(store.trend.advice).font(.subheadline)
            if let adjustment = store.trend.calorieAdjustment {
                Button(L10n.text("Preview suggested target: %@ kcal", String(describing: (store.profile.calorieTarget + adjustment).wholeText))) {
                    calories = store.profile.calorieTarget + adjustment
                }
                Text(L10n.text("The suggestion is only applied when you tap Save.")).font(.caption)
            }
        }
    }

    private var profileSection: some View {
        Section(L10n.text("Profile")) {
            TextField(L10n.text("Name"), text: $name)
            NumberField(title: L10n.text("Height (cm)"), value: $height)
            NumberField(title: L10n.text("Starting weight (kg)"), value: $startingWeight)
            Text(L10n.text("Goal: lean muscle gain and gym performance while preserving badminton performance.")).font(.caption)
        }
    }
    private func loadProfile() {
        guard !loaded else { return }; loaded = true
        goalWeight = library.state.goalWeightKG ?? 0
        let p = store.profile
        name = p.name; height = p.heightCM; startingWeight = p.startingWeightKG
        calories = p.calorieTarget; protein = p.proteinTarget; fat = p.fatTarget
        yogurt = p.breakfastYogurtGrams; banana = p.breakfastBananaGrams; oats = p.breakfastOatsGrams
    }
    private func save() {
        guard valid, library.update({ $0.goalWeightKG = goalWeight > 0 ? goalWeight : nil }) else { return }
        let p = store.profile
        p.name = name; p.heightCM = height; p.startingWeightKG = startingWeight
        p.calorieTarget = calories; p.proteinTarget = protein; p.fatTarget = fat
        p.breakfastYogurtGrams = yogurt; p.breakfastBananaGrams = banana; p.breakfastOatsGrams = oats
        if store.save() { dismiss() }
    }
}

struct InventoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var name = ""
    var body: some View {
        List {
            Section {
                TextField(L10n.text("Food name (e.g. eggs, rice, chicken)"), text: $name).onSubmit { add() }
                Button(L10n.text("Add food")) { add() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section(L10n.text("Currently at home")) {
                if store.inventory.isEmpty { Text(L10n.text("Add what you have. Meal suggestions prioritize matching foods.")).foregroundStyle(.secondary) }
                ForEach(store.inventory) { food in
                    Text(food.name).swipeActions { Button(L10n.text("Remove"), role: .destructive) { store.removeInventory(food) } }
                }
            }
        }.navigationTitle(L10n.text("Inventory"))
    }
    private func add() { if store.addInventory(name) { name = "" } }
}

struct HealthPermissionsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    var body: some View {
        List {
            readAccessSection
            permissionHelpSection
            Section(L10n.text("Readable Health data")) {
                MetricRow(title: L10n.text("Steps"), value: health.steps?.wholeText ?? L10n.text("No readable data"))
                MetricRow(title: L10n.text("Active calories"), value: health.activeCalories.map { L10n.text("%@ kcal", $0.wholeText) } ?? L10n.text("No readable data"))
                MetricRow(title: L10n.text("Latest heart rate today"), value: health.heartRate.map { L10n.text("%@ bpm", $0.wholeText) } ?? L10n.text("No readable data"))
            }
        }.calmList().navigationTitle(L10n.text("Apple Health"))
    }

    private var permissionHelpSection: some View {
        Section(L10n.text("Manage permissions")) {
            Text(L10n.text("To change previously granted or denied access, open the Health app → your profile → Apps and Services → LeanLog. A repeated request may not show a new permission prompt."))
            Text(L10n.text("Apple does not expose read-denial status. Missing values mean either no readable samples or no permission, not zero activity. Manual food, weight and training logging still work."))
            Text(L10n.text("Weight and sleep already imported remain cached locally when access is later revoked. The app does not write to Health. If you delete an imported weight here, a future Health refresh can import it again.")).font(.caption)
        }
    }

    private var readAccessSection: some View {
        Section(L10n.text("Read-only access")) {
            Text(L10n.text("Read steps, active calories, heart rate, workouts, sleep and body weight from Apple Health. Apple Watch records arrive through Health; no separate Watch app is required."))
            Button(L10n.text("Request / review Health access")) { Task { if await health.requestAccess() { await health.refresh(into: store) } } }
                .disabled(!health.available || health.isLoading || health.isRequestingAccess)
            Button(health.isLoading ? L10n.text("Refreshing…") : L10n.text("Refresh Health data")) { Task { await health.refresh(into: store) } }
                .disabled(!health.available || !health.requestedAccess || health.isLoading || health.isRequestingAccess)
            if !health.available { Text(L10n.text("Apple Health is unavailable on this device. Manual tracking remains available.")).foregroundStyle(.secondary) }
            Text(health.message).font(.subheadline)
            if let date = health.refreshedAt { Text(L10n.text("Last refresh: %@", String(describing: date.formatted()))).font(.caption) }
        }
    }
}
