import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @EnvironmentObject private var analysisSettings: FoodAnalysisSettings
    var body: some View {
        List {
            Section("Personal settings") {
                NavigationLink("Profile, targets & breakfast") { ProfileEditor() }
                Toggle("Display weight in pounds", isOn: Binding(get: { store.profile.usesPounds }, set: { store.profile.usesPounds = $0; store.save() }))
                NavigationLink("Food inventory (\(store.inventory.count))") { InventoryView() }
                Text("Stored on this iPhone with SwiftData. No account, backend, cloud sync or Health writes.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Apple Health / Watch") {
                NavigationLink("Health permissions & data") { HealthPermissionsView() }
                Text(health.message).font(.caption).foregroundStyle(.secondary)
            }
            Section("Food photo analysis") {
                NavigationLink("Provider & API credentials") { FoodAnalysisSettingsView() }
                Text(analysisSettings.configuration.mode.label).font(.caption).foregroundStyle(.secondary)
                Text("Analyze a photo, review detected foods and portions, then edit before saving. Manual logging always works.").font(.caption)
            }
        }.navigationTitle("Settings")
    }
}

struct ProfileEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
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
        EntryValidation.profile(height: height, startingWeight: startingWeight, calories: calories,
            protein: protein, fat: fat, yogurt: yogurt, banana: banana, oats: oats)
    }
    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $name)
                NumberField(title: "Height (cm)", value: $height)
                NumberField(title: "Starting weight (kg)", value: $startingWeight)
                Text("Goal: lean muscle gain and gym performance while preserving badminton performance.").font(.caption)
            }
            Section("Daily targets") {
                NumberField(title: "Calories (kcal)", value: $calories)
                NumberField(title: "Protein (g)", value: $protein)
                NumberField(title: "Fat (g)", value: $fat)
                Text("Remaining energy from carbs: about \(max(0, (calories - protein * 4 - fat * 9) / 4).formatted(.number.precision(.fractionLength(0)))) g. Initial target is 2700 kcal, 130 g protein and 70 g fat.").font(.caption)
                Text(store.trend.advice).font(.subheadline)
                if let adjustment = store.trend.calorieAdjustment {
                    Button("Preview suggested target: \((store.profile.calorieTarget + adjustment).wholeText) kcal") {
                        calories = store.profile.calorieTarget + adjustment
                    }
                    Text("The suggestion is only applied when you tap Save.").font(.caption)
                }
            }
            Section("Automatic daily breakfast") {
                NumberField(title: "Greek yogurt (g)", value: $yogurt)
                NumberField(title: "Banana (g)", value: $banana)
                NumberField(title: "Oats (g)", value: $oats)
                let breakfast = FitnessLogic.breakfast(yogurt: yogurt, banana: banana, oats: oats)
                Text("≈ \(breakfast.calories.formatted(.number.precision(.fractionLength(0)))) kcal · \(breakfast.protein.formatted(.number.precision(.fractionLength(0)))) g protein")
                Text("The default is about 486 kcal and 29 g protein. Changing breakfast portions does not change meals already logged.").font(.caption)
            }
            if !valid { Section { Text("Check values: calories 1000–6000, protein 30–300 g, fat 20–200 g, and positive breakfast portions. Protein and fat energy must fit the calorie target.").foregroundStyle(.red) } }
        }.navigationTitle("Profile & targets").keyboardDoneButton()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid) } }
            .task {
                guard !loaded else { return }; loaded = true
                let p = store.profile
                name = p.name; height = p.heightCM; startingWeight = p.startingWeightKG
                calories = p.calorieTarget; protein = p.proteinTarget; fat = p.fatTarget
                yogurt = p.breakfastYogurtGrams; banana = p.breakfastBananaGrams; oats = p.breakfastOatsGrams
            }
    }
    private func save() {
        guard valid else { return }
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
                TextField("Food name (e.g. eggs, rice, chicken)", text: $name).onSubmit { add() }
                Button("Add food") { add() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Currently at home") {
                if store.inventory.isEmpty { Text("Add what you have. Meal suggestions prioritize matching foods.").foregroundStyle(.secondary) }
                ForEach(store.inventory) { food in
                    Text(food.name).swipeActions { Button("Remove", role: .destructive) { store.removeInventory(food) } }
                }
            }
        }.navigationTitle("Inventory")
    }
    private func add() { if store.addInventory(name) { name = "" } }
}

struct HealthPermissionsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    var body: some View {
        List {
            Section("Read-only access") {
                Text("Read steps, active calories, heart rate, workouts, sleep and body weight from Apple Health. Apple Watch records arrive through Health; no separate Watch app is required.")
                Button("Request / review Health access") { Task { if await health.requestAccess() { await health.refresh(into: store) } } }
                    .disabled(!health.available || health.isLoading || health.isRequestingAccess)
                Button(health.isLoading ? "Refreshing…" : "Refresh Health data") { Task { await health.refresh(into: store) } }
                    .disabled(!health.available || !health.requestedAccess || health.isLoading || health.isRequestingAccess)
                if !health.available { Text("Apple Health is unavailable on this device. Manual tracking remains available.").foregroundStyle(.secondary) }
                Text(health.message).font(.subheadline)
                if let date = health.refreshedAt { Text("Last refresh: \(date.formatted())").font(.caption) }
            }
            Section("Manage permissions") {
                Text("To change previously granted or denied access, open the Health app → your profile → Apps and Services → LeanLog. A repeated request may not show a new permission prompt.")
                Text("Apple does not expose read-denial status. Missing values mean either no readable samples or no permission, not zero activity. Manual food, weight and training logging still work.")
                Text("Weight and sleep already imported remain cached locally when access is later revoked. The app does not write to Health. If you delete an imported weight here, a future Health refresh can import it again.").font(.caption)
            }
        }.navigationTitle("Apple Health")
    }
}
