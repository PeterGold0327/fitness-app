import SwiftUI

struct TrainingStartView: View {
    @EnvironmentObject private var library: PersonalLibrary
    @EnvironmentObject private var store: AppStore
    @Binding var sheet: AppSheet?
    var body: some View {
        List {
            Section(L10n.text("Choose your workout")) {
                ForEach(library.state.workouts) { template in
                    Button {
                        library.plan(template.id, date: store.currentDate)
                        sheet = .template(template.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.text(template.id.title)).font(.title3.bold())
                            Text(template.exercises.filter { !$0.accessory }.map { L10n.text($0.name) }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("training.template.\(template.id.rawValue)")
                }
            }
            Section {
                Text(L10n.text("Choose when to train. Templates set exercise names, not mandatory sets or reps.")).font(.caption).foregroundStyle(.secondary)
                NavigationLink(L10n.text("Edit workout templates")) { WorkoutTemplatesEditor() }
                Button(L10n.text("Log gym workout")) { sheet = .workout(nil) }
            }
            if let error = library.error { Section { Text(error).foregroundStyle(.red) } }
        }.calmList().navigationTitle(L10n.text("Start training"))
    }
}
struct WorkoutTemplatesEditor: View {
    @EnvironmentObject private var library: PersonalLibrary
    var body: some View {
        List {
            ForEach(library.state.workouts) { template in
                NavigationLink(L10n.text(template.id.title)) { WorkoutTemplateEditor(template: template) }
            }
        }.calmList().navigationTitle(L10n.text("Workout templates"))
    }
}
private struct WorkoutTemplateEditor: View {
    @EnvironmentObject private var library: PersonalLibrary
    @Environment(\.dismiss) private var dismiss
    @State var template: WorkoutTemplate
    var body: some View {
        Form {
            ForEach($template.exercises) { $exercise in
                Section {
                    TextField(L10n.text("Exercise name"), text: $exercise.name)
                    Toggle(L10n.text("Optional badminton accessory"), isOn: $exercise.accessory)
                    Button(L10n.text("Remove exercise"), role: .destructive) { template.exercises.removeAll { $0.id == exercise.id } }
                }
            }
            Button(L10n.text("Add exercise")) { template.exercises.append(TemplateExercise(name: "")) }.disabled(template.exercises.count >= 20)
            Text(L10n.text("Keep at most one optional athletic accessory. Sets and reps are chosen when logging.")).font(.caption)
            if let error = library.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle(L10n.text(template.id.title)).keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Save")) {
                        if library.update({ state in
                            if let index = state.workouts.firstIndex(where: { $0.id == template.id }) { state.workouts[index] = template }
                        }) { dismiss() }
                    }.disabled(!template.valid)
                }
            }
    }
}
struct SetDraft: Identifiable {
    var id = UUID()
    var weight = 0.0
    var reps = Double.nan
    var rpe = 8.0
    var valid: Bool { weight.isFinite && weight >= 0 && weight <= 2204.6227 && reps.isFinite && reps.rounded() == reps && (1...100).contains(reps) }
}
struct TemplateExerciseDraft: Identifiable {
    var id = UUID()
    var name: String
    var sets: [SetDraft]
    var notes = ""
}
struct TemplateWorkoutEditor: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var library: PersonalLibrary
    @Environment(\.dismiss) private var dismiss
    var split: TrainingSplit
    @State private var date = Date()
    @State private var exercises: [TemplateExerciseDraft] = []
    @State private var loaded = false
    @State private var saved = false
    @State private var summary: [String] = []
    @State private var includeAccessory = false
    @State private var minutes = 0.0
    @State private var activeCalories = 0.0
    private var template: WorkoutTemplate? { library.state.workouts.first { $0.id == split } }
    private var valid: Bool { minutes.isFinite && activeCalories.isFinite && (0...600).contains(minutes) && (0...10000).contains(activeCalories) && (activeCalories == 0 || minutes >= 1) && !exercises.isEmpty && exercises.count <= 20 && exercises.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.sets.isEmpty && $0.sets.count <= 30 && $0.sets.allSatisfy(\.valid) } }
    var body: some View {
        NavigationStack {
            Form {
                if saved {
                    Section(L10n.text("Workout saved")) { ForEach(Array(summary.enumerated()), id: \.offset) { Text($0.element) } }
                } else {
                    Section {
                        DatePicker(L10n.text("Date"), selection: $date, in: ...Date())
                        Text(L10n.text("Previous loads are filled in. Enter only the reps and weights you actually complete.")).font(.caption)
                    }
                    DisclosureGroup(L10n.text("Manual activity details (optional)")) {
                        NumberField(title: L10n.text("Duration in minutes (optional)"), value: $minutes)
                        NumberField(title: L10n.text("Active calories (optional)"), value: $activeCalories)
                        Text(L10n.text("Only enter duration or energy when Health has no readable workout. Leave zero if unknown.")).font(.caption)
                    }
                    ForEach($exercises) { $exercise in exerciseCard($exercise) }
                    if let accessory = template?.exercises.first(where: \.accessory), !includeAccessory {
                        Button(L10n.text("Add optional accessory: %@", L10n.text(accessory.name))) {
                            exercises.append(draft(accessory)); includeAccessory = true
                        }
                    }
                    Button(L10n.text("Add exercise")) { exercises.append(TemplateExerciseDraft(name: "", sets: [SetDraft()])) }.disabled(exercises.count >= 20)
                }
                if let error = library.error { Section { Text(error).foregroundStyle(.red) } }
            }.calmList().navigationTitle(L10n.text(split.title)).keyboardDoneButton()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(saved ? L10n.text("Done") : L10n.text("Cancel")) { dismiss() } }
                    if !saved { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Save")) { save() }.disabled(!valid) } }
                }
                .task {
                    guard !loaded else { return }; loaded = true
                    date = store.currentDate
                    exercises = template?.exercises.filter { !$0.accessory }.map(draft) ?? []
                }
        }
    }
    private func draft(_ exercise: TemplateExercise) -> TemplateExerciseDraft {
        let previous = store.exerciseHistory(exercise.name, before: date).first
        let sets = previous?.sets.map { SetDraft(weight: store.displayedWeight($0.weightKG), rpe: $0.rpe) } ?? [SetDraft()]
        return TemplateExerciseDraft(name: L10n.text(exercise.name), sets: sets)
    }
    private func exerciseCard(_ binding: Binding<TemplateExerciseDraft>) -> some View {
        let exercise = binding.wrappedValue
        let history = store.exerciseHistory(exercise.name, before: date)
        return Section {
            TextField(L10n.text("Exercise name"), text: binding.name).font(.headline)
            if let last = history.first {
                Text(L10n.text("Previous Workout") + " · " + last.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                Text(last.sets.map { L10n.text("%@ × %@", store.weightText($0.weightKG), String($0.reps)) }.joined(separator: " / ")).font(.subheadline)
            } else { Text(L10n.text("No previous session for this exercise.")).font(.caption).foregroundStyle(.secondary) }
            Text(TrainingCoach.advice(history, now: date, sleepHours: store.latestSleep?.hours)).font(.callout).foregroundStyle(.teal)
            Text(L10n.text("Today's Workout")).font(.caption.weight(.semibold))
            ForEach(binding.sets) { set in
                HStack {
                    NumberField(title: L10n.text("Weight (%@)", store.profile.usesPounds ? L10n.text("lb") : L10n.text("kg")), value: set.weight)
                    NumberField(title: L10n.text("Reps"), value: set.reps, allowsBlank: true)
                    Button { binding.wrappedValue.sets.removeAll { $0.id == set.wrappedValue.id } } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel(L10n.text("Remove set")).disabled(exercise.sets.count <= 1)
                }
            }
            Button(L10n.text("Add set")) { binding.wrappedValue.sets.append(SetDraft(weight: exercise.sets.last?.weight ?? 0)) }.disabled(exercise.sets.count >= 30)
            Button(L10n.text("Skip this exercise")) { exercises.removeAll { $0.id == exercise.id } }
            DisclosureGroup(L10n.text("Details (optional)")) {
                TextField(L10n.text("Notes (optional)"), text: binding.notes, axis: .vertical)
                ForEach(binding.sets) { set in
                    Stepper(L10n.text("RPE: %@", set.wrappedValue.rpe.formatted()), value: set.rpe, in: 1...10, step: 0.5)
                }
                Button(L10n.text("Remove exercise"), role: .destructive) { exercises.removeAll { $0.id == exercise.id } }
            }
        }
    }
    private func save() {
        guard valid, !saved else { return }
        var comparisons: [String] = []
        var entries: [ExerciseEntry] = []
        for exercise in exercises {
            let previous = store.exerciseHistory(exercise.name, before: date).first
            let actual = exercise.sets.map { TrainingSet(weightKG: store.kilograms(from: $0.weight), reps: Int($0.reps), rpe: $0.rpe) }
            comparisons.append(exercise.name + ": " + TrainingCoach.comparison(today: actual, previous: previous?.sets ?? []))
            for (index, set) in actual.enumerated() {
                entries.append(ExerciseEntry(name: exercise.name, weightKG: set.weightKG, sets: 1, reps: set.reps,
                    targetReps: previous?.sets.indices.contains(index) == true ? previous!.sets[index].reps : set.reps,
                    rpe: set.rpe, targetSets: 1, isLegExercise: split == .legs, notes: exercise.notes))
            }
        }
        if store.saveWorkout(nil, name: L10n.text(split.title), date: date, exercises: entries) {
            if minutes >= 1 {
                library.update { state in
                    state.manualActivities.append(ManualActivityRecord(date: date, badminton: false, workoutID: store.workouts.first { $0.date == date && $0.name == L10n.text(split.title) }?.id, minutes: minutes, activeCalories: activeCalories > 0 ? activeCalories : nil))
                }
            }
            summary = comparisons; saved = true
        }
    }
}
struct GymSessionDetail: View {
    @EnvironmentObject private var store: AppStore
    var session: WorkoutSession
    @Binding var sheet: AppSheet?
    private var names: [String] {
        var seen = Set<String>()
        return session.exercises.sorted { $0.position < $1.position }.compactMap { seen.insert(TrainingCoach.canonical($0.name)).inserted ? $0.name : nil }
    }
    var body: some View {
        List {
            Text(session.date.formatted(date: .abbreviated, time: .shortened))
            ForEach(names, id: \.self) { name in
                let rows = session.exercises.sorted { $0.position < $1.position }.filter { TrainingCoach.canonical($0.name) == TrainingCoach.canonical(name) }
                Section(name) {
                    ForEach(rows) { row in Text(L10n.text("%@ · %@ × %@", store.weightText(row.weightKG), String(row.sets), String(row.reps))) }
                    let history = store.exerciseHistory(name, before: session.date, excluding: session.id)
                    if let last = history.first {
                        Text(L10n.text("Previous Workout") + " · " + last.date.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                        Text(last.sets.map { L10n.text("%@ × %@", store.weightText($0.weightKG), String($0.reps)) }.joined(separator: " / "))
                    }
                }
            }
            Button(L10n.text("Edit session")) { sheet = .workout(session) }
        }.calmList().navigationTitle(session.name)
    }
}
