import SwiftUI

struct TrainingView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @Binding var sheet: AppSheet?
    var body: some View {
        List {
            Section {
                Button(L10n.text("Log gym workout")) { sheet = .workout(nil) }
                Button(L10n.text("Log badminton / add upcoming date")) { sheet = .badminton }
                Text(L10n.text("You own your plan. Suggestions never change it automatically.")).font(.caption).foregroundStyle(.secondary)
            }
            suggestionsSection
            gymLogSection
            badmintonSection
            healthWorkoutsSection
        }.navigationTitle(L10n.text("Training"))
    }

    private var healthWorkoutsSection: some View {
        Section(L10n.text("Apple Health workouts · last 7 days")) {
            if health.workouts.isEmpty { Text(L10n.text("No readable workouts. Connect Health in Settings.")).foregroundStyle(.secondary) }
            ForEach(health.workouts) { workout in
                VStack(alignment: .leading) {
                    Text(L10n.text("%@ · %@ min", String(describing: workout.label), String(describing: (workout.minutes).wholeText)))
                    Text(workout.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(L10n.text("Health activity informs meal suggestions and badminton warnings. Workouts stay read-only and separate from your gym sets and badminton dates. Log sets yourself for progression advice.")).font(.caption)
        }
    }

    private var badmintonSection: some View {
        Section(L10n.text("Badminton dates")) {
            if store.badminton.isEmpty { Text(L10n.text("No dates logged.")).foregroundStyle(.secondary) }
            ForEach(store.badminton) { entry in
                Text(entry.day.formatted(date: .abbreviated, time: .omitted))
                    .swipeActions { Button(L10n.text("Delete"), role: .destructive) { store.deleteBadminton(entry) } }
            }
        }
    }

    private var gymLogSection: some View {
        Section(L10n.text("Gym log")) {
            if store.workouts.isEmpty { Text(L10n.text("No workouts yet. Log your first-week plan to establish a baseline.")).foregroundStyle(.secondary) }
            ForEach(store.workouts) { session in
                DisclosureGroup {
                    ForEach(session.exercises.sorted { $0.position < $1.position }) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name).font(.headline)
                            Text(L10n.text("%@ · %@ × %@ · target %@ × %@ · RPE %@", String(describing: store.weightText(exercise.weightKG)), String(describing: exercise.sets), String(describing: exercise.reps), String(describing: exercise.targetSets), String(describing: exercise.targetReps), String(describing: String(format: "%.1f", locale: Locale.current, exercise.rpe))))
                            if !exercise.notes.isEmpty { Text(exercise.notes).foregroundStyle(.secondary) }
                        }.font(.subheadline)
                    }
                    if let warning = FitnessLogic.legWarning(gymDate: session.date,
                        heavyLegs: session.exercises.contains { $0.isLegExercise && $0.rpe >= 8 },
                        badmintonDates: store.badmintonDates) { Text(warning).foregroundStyle(.orange) }
                    Button(L10n.text("Edit session")) { sheet = .workout(session) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(session.name)
                        Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions { Button(L10n.text("Delete"), role: .destructive) { store.deleteWorkout(session) } }
            }
        }
    }

    private var suggestionsSection: some View {
        Section(L10n.text("Next-week suggestions")) {
            Text(store.weeklyVolumeAdvice)
            ForEach(store.recentExerciseNames, id: \.self) { name in
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.headline)
                    Text(store.exerciseAdvice(name: name)).font(.subheadline)
                }
            }
        }
    }
}

struct ExerciseDraft: Identifiable {
    var id = UUID()
    var name = ""
    var displayedWeight = 0.0
    var sets = 3
    var targetSets = 3
    var reps = 8
    var targetReps = 8
    var rpe = 7.0
    var isLegExercise = false
    var notes = ""
    var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayedWeight <= 2204.63 &&
        ExercisePerformance(date: .now, weight: displayedWeight, sets: sets, reps: reps,
            targetReps: targetReps, rpe: rpe, targetSets: targetSets).valid
    }
}

struct WorkoutEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var existing: WorkoutSession? = nil
    @State private var name = L10n.text("Gym")
    @State private var date = Date()
    @State private var exercises = [ExerciseDraft()]
    @State private var loaded = false
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                sessionSection
                ForEach($exercises) { $exercise in
                    exerciseSection($exercise)
                }
                Section { Button(L10n.text("Add exercise")) { exercises.append(ExerciseDraft()) } }
                if let warning = FitnessLogic.legWarning(gymDate: date,
                    heavyLegs: exercises.contains { $0.isLegExercise && $0.rpe >= 8 }, badmintonDates: store.badmintonDates) {
                    Section(L10n.text("Schedule suggestion")) { Text(warning).foregroundStyle(.orange) }
                }
            }.navigationTitle(existing == nil ? L10n.text("Log workout") : L10n.text("Edit workout")).keyboardDoneButton()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("Save")) { save() }.disabled(saving || exercises.isEmpty || !exercises.allSatisfy(\.valid) || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .task {
                    guard !loaded else { return }; loaded = true
                    if let existing {
                        name = existing.name; date = existing.date
                        exercises = existing.exercises.sorted { $0.position < $1.position }.map {
                            ExerciseDraft(name: $0.name, displayedWeight: store.displayedWeight($0.weightKG), sets: $0.sets, targetSets: $0.targetSets,
                                          reps: $0.reps, targetReps: $0.targetReps, rpe: $0.rpe, isLegExercise: $0.isLegExercise, notes: $0.notes)
                        }
                    }
                }
        }
    }

    private var sessionSection: some View {
        Section(L10n.text("Session")) {
            TextField(L10n.text("Workout name"), text: $name)
            DatePicker(L10n.text("Date"), selection: $date, in: ...Date())
            Text(L10n.text("Use one row per exercise. Sets share the logged weight and reps; use another row for different loads.")).font(.caption)
        }
    }
    private func exerciseSection(_ binding: Binding<ExerciseDraft>) -> some View {
        let exercise = binding.wrappedValue
        return Section(L10n.text("Exercise")) {
            TextField(L10n.text("Exercise name"), text: binding.name)
            NumberField(title: L10n.text("Weight (%@)", String(describing: store.profile.usesPounds ? L10n.text("lb") : L10n.text("kg"))), value: binding.displayedWeight)
            Stepper(L10n.text("Sets completed: %@", String(describing: exercise.sets)), value: binding.sets, in: 0...30)
            Stepper(L10n.text("Target sets: %@", String(describing: exercise.targetSets)), value: binding.targetSets, in: 1...30)
            Stepper(L10n.text("Reps completed per set: %@", String(describing: exercise.reps)), value: binding.reps, in: 0...100)
            Stepper(L10n.text("Target reps per set: %@", String(describing: exercise.targetReps)), value: binding.targetReps, in: 1...100)
            Stepper(L10n.text("RPE: %@", String(describing: String(format: "%.1f", locale: Locale.current, exercise.rpe))), value: binding.rpe, in: 1...10, step: 0.5)
            Toggle(L10n.text("Leg exercise"), isOn: binding.isLegExercise)
            TextField(L10n.text("Notes (optional)"), text: binding.notes, axis: .vertical)
            if exercises.count > 1 {
                Button(L10n.text("Remove exercise"), role: .destructive) { exercises.removeAll { $0.id == exercise.id } }
            }
        }
    }
    private func save() {
        guard !saving, !exercises.isEmpty, exercises.allSatisfy(\.valid) else { return }
        saving = true
        let entries = exercises.map {
            ExerciseEntry(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), weightKG: store.kilograms(from: $0.displayedWeight),
                sets: $0.sets, reps: $0.reps, targetReps: $0.targetReps, rpe: $0.rpe, targetSets: $0.targetSets,
                isLegExercise: $0.isLegExercise, notes: $0.notes)
        }
        if store.saveWorkout(existing, name: name, date: date, exercises: entries) { dismiss() }
        else { saving = false }
    }
}

struct BadmintonEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L10n.text("Badminton date"), selection: $date, displayedComponents: .date)
                Text(L10n.text("One entry per day. Upcoming dates help flag heavy leg sessions nearby; only completed dates count toward weekly summaries.")).font(.caption)
            }.navigationTitle(L10n.text("Badminton"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Save")) { if store.logBadminton(date: date) { dismiss() } } }
                }
        }
    }
}
