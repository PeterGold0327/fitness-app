import SwiftUI

struct TrainingView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @Binding var sheet: AppSheet?
    var body: some View {
        List {
            Section {
                Button("Log gym workout") { sheet = .workout(nil) }
                Button("Log badminton / add upcoming date") { sheet = .badminton }
                Text("You own your plan. Suggestions never change it automatically.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Next-week suggestions") {
                Text(store.weeklyVolumeAdvice)
                ForEach(store.recentExerciseNames, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(name).font(.headline)
                        Text(store.exerciseAdvice(name: name)).font(.subheadline)
                    }
                }
            }
            Section("Gym log") {
                if store.workouts.isEmpty { Text("No workouts yet. Log your first-week plan to establish a baseline.").foregroundStyle(.secondary) }
                ForEach(store.workouts) { session in
                    DisclosureGroup {
                        ForEach(session.exercises.sorted { $0.position < $1.position }) { exercise in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name).font(.headline)
                                Text("\(store.weightText(exercise.weightKG)) · \(exercise.sets) × \(exercise.reps) · target \(exercise.targetSets) × \(exercise.targetReps) · RPE \(exercise.rpe, specifier: "%.1f")")
                                if !exercise.notes.isEmpty { Text(exercise.notes).foregroundStyle(.secondary) }
                            }.font(.subheadline)
                        }
                        if let warning = FitnessLogic.legWarning(gymDate: session.date,
                            heavyLegs: session.exercises.contains { $0.isLegExercise && $0.rpe >= 8 },
                            badmintonDates: store.badmintonDates) { Text(warning).foregroundStyle(.orange) }
                        Button("Edit session") { sheet = .workout(session) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(session.name)
                            Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { store.deleteWorkout(session) } }
                }
            }
            Section("Badminton dates") {
                if store.badminton.isEmpty { Text("No dates logged.").foregroundStyle(.secondary) }
                ForEach(store.badminton) { entry in
                    Text(entry.day.formatted(date: .abbreviated, time: .omitted))
                        .swipeActions { Button("Delete", role: .destructive) { store.deleteBadminton(entry) } }
                }
            }
            Section("Apple Health workouts · last 7 days") {
                if health.workouts.isEmpty { Text("No readable workouts. Connect Health in Settings.").foregroundStyle(.secondary) }
                ForEach(health.workouts) { workout in
                    VStack(alignment: .leading) {
                        Text("\(workout.label) · \((workout.minutes).wholeText) min")
                        Text(workout.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Health activity informs meal suggestions and badminton warnings. Workouts stay read-only and separate from your gym sets and badminton dates. Log sets yourself for progression advice.").font(.caption)
            }
        }.navigationTitle("Training")
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
    @State private var name = "Gym"
    @State private var date = Date()
    @State private var exercises = [ExerciseDraft()]
    @State private var loaded = false
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Workout name", text: $name)
                    DatePicker("Date", selection: $date, in: ...Date())
                    Text("Use one row per exercise. Sets share the logged weight and reps; use another row for different loads.").font(.caption)
                }
                ForEach($exercises) { $exercise in
                    Section("Exercise") {
                        TextField("Exercise name", text: $exercise.name)
                        NumberField(title: "Weight (\(store.profile.usesPounds ? "lb" : "kg"))", value: $exercise.displayedWeight)
                        Stepper("Sets completed: \(exercise.sets)", value: $exercise.sets, in: 0...30)
                        Stepper("Target sets: \(exercise.targetSets)", value: $exercise.targetSets, in: 1...30)
                        Stepper("Reps completed per set: \(exercise.reps)", value: $exercise.reps, in: 0...100)
                        Stepper("Target reps per set: \(exercise.targetReps)", value: $exercise.targetReps, in: 1...100)
                        Stepper("RPE: \(exercise.rpe, specifier: "%.1f")", value: $exercise.rpe, in: 1...10, step: 0.5)
                        Toggle("Leg exercise", isOn: $exercise.isLegExercise)
                        TextField("Notes (optional)", text: $exercise.notes, axis: .vertical)
                        if exercises.count > 1 {
                            Button("Remove exercise", role: .destructive) { exercises.removeAll { $0.id == exercise.id } }
                        }
                    }
                }
                Section { Button("Add exercise") { exercises.append(ExerciseDraft()) } }
                if let warning = FitnessLogic.legWarning(gymDate: date,
                    heavyLegs: exercises.contains { $0.isLegExercise && $0.rpe >= 8 }, badmintonDates: store.badmintonDates) {
                    Section("Schedule suggestion") { Text(warning).foregroundStyle(.orange) }
                }
            }.navigationTitle(existing == nil ? "Log workout" : "Edit workout").keyboardDoneButton()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.disabled(saving || exercises.isEmpty || !exercises.allSatisfy(\.valid) || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                DatePicker("Badminton date", selection: $date, displayedComponents: .date)
                Text("One entry per day. Upcoming dates help flag heavy leg sessions nearby; only completed dates count toward weekly summaries.").font(.caption)
            }.navigationTitle("Badminton")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.logBadminton(date: date) { dismiss() } } }
                }
        }
    }
}
