import Foundation

enum TrainingSplit: String, Codable, CaseIterable, Identifiable {
    case chest, shoulders, back, legs
    var id: String { rawValue }
    var title: String {
        switch self { case .chest: return "Chest"; case .shoulders: return "Shoulders"; case .back: return "Back"; case .legs: return "Legs" }
    }
}
struct TemplateExercise: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var accessory = false
}
struct WorkoutTemplate: Codable, Identifiable, Equatable {
    var id: TrainingSplit
    var exercises: [TemplateExercise]
    var valid: Bool {
        !exercises.isEmpty && exercises.count <= 20 && exercises.filter(\.accessory).count <= 1 &&
        Set(exercises.map(\.id)).count == exercises.count && exercises.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 200 }
    }
    static var defaults: [WorkoutTemplate] {
        func template(_ split: TrainingSplit, _ names: [String], _ accessory: String) -> WorkoutTemplate {
            WorkoutTemplate(id: split, exercises: names.map { TemplateExercise(name: $0) } + [TemplateExercise(name: accessory, accessory: true)])
        }
        return [template(.chest, ["Bench Press", "Incline Dumbbell Press", "Cable Fly", "Machine Chest Press"], "Explosive Push-up"),
                template(.shoulders, ["Shoulder Press", "Lateral Raise", "Cable Lateral Raise", "Reverse Fly"], "Rotational Medicine Ball Throw"),
                template(.back, ["Lat Pulldown", "Seated Row", "Chest-supported Row", "Straight-arm Pulldown"], "Pallof Press"),
                template(.legs, ["Squat", "Romanian Deadlift", "Bulgarian Split Squat", "Leg Curl", "Calf Raise"], "Lateral Bounds")]
    }
}
struct TrainingSet: Equatable {
    var weightKG: Double
    var reps: Int
    var rpe: Double = 8
    var valid: Bool { weightKG.isFinite && (0...1000).contains(weightKG) && (1...100).contains(reps) && rpe.isFinite && (1...10).contains(rpe) }
}
struct ExerciseSessionSnapshot: Identifiable {
    var id: UUID
    var date: Date
    var sets: [TrainingSet]
    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
}
enum TrainingCoach {
    static func canonical(_ name: String) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases: [[String]] = [
            ["bench press", "barbell bench press", "杠铃卧推", "平板卧推", "卧推"],
            ["incline dumbbell press", "上斜哑铃卧推"], ["cable fly", "绳索夹胸", "夹胸"],
            ["machine chest press", "器械胸推"], ["shoulder press", "肩推"],
            ["lateral raise", "侧平举"], ["cable lateral raise", "绳索侧平举"], ["reverse fly", "后束飞鸟"],
            ["lat pulldown", "高位下拉"], ["seated row", "坐姿划船"], ["chest-supported row", "胸托划船"],
            ["straight-arm pulldown", "直臂下压"], ["squat", "深蹲"], ["romanian deadlift", "罗马尼亚硬拉"],
            ["bulgarian split squat", "保加利亚分腿蹲"], ["leg curl", "腿弯举"], ["calf raise", "小腿提踵"]]
        return aliases.first { $0.contains(normalized) }?.first ?? normalized
    }
    static func previous(_ history: [ExerciseSessionSnapshot], before date: Date, excluding id: UUID? = nil) -> [ExerciseSessionSnapshot] {
        history.filter { $0.date < date && $0.id != id && !$0.sets.isEmpty && $0.sets.allSatisfy(\.valid) }.sorted { $0.date > $1.date }
    }
    static func advice(_ history: [ExerciseSessionSnapshot], now: Date, sleepHours: Double? = nil) -> String {
        let sessions = previous(history, before: now)
        guard let last = sessions.first else { return L10n.text("First session: choose a comfortable load and record the reps you actually complete.") }
        if let hours = sleepHours, hours > 0 && hours < 6 { return L10n.text("Sleep was short; keep the previous load and stop before straining.") }
        if now.timeIntervalSince(last.date) > 21 * 86400 { return L10n.text("Returning after a gap: start at or below the previous load and keep the first session comfortable.") }
        if sessions.count >= 3 {
            let recent = Array(sessions.prefix(3))
            let loads = recent.map { $0.sets.map(\.weightKG) }
            if loads[0] == loads[1], loads[1] == loads[2], recent[0].totalReps < recent[1].totalReps, recent[1].totalReps < recent[2].totalReps {
                return L10n.text("Reps fell in the last two sessions at the same load. Keep the weight steady this time.")
            }
        }
        if last.sets.allSatisfy({ $0.reps >= 10 && $0.rpe <= 7 }) { return L10n.text("All previous sets felt comfortable. Consider a small load increase next time.") }
        let upper = max(10, last.sets.map(\.reps).max() ?? 10)
        let uneven = last.sets.contains { $0.reps < upper }
        let reps = last.sets.enumerated().map {
            String(min(100, uneven ? min(upper, $0.element.reps + 1) : $0.element.reps + ($0.offset < 2 ? 1 : 0)))
        }.joined(separator: " / ")
        return L10n.text("Keep the previous load; aim for %@ reps if comfortable.", reps)
    }
    static func comparison(today: [TrainingSet], previous: [TrainingSet]) -> String {
        guard !today.isEmpty, today.allSatisfy(\.valid), !previous.isEmpty else { return L10n.text("This session establishes your baseline.") }
        guard today.map(\.weightKG) == previous.map(\.weightKG) else { return L10n.text("Loads or set count changed. Use this session as the next comparison.") }
        let difference = today.reduce(0) { $0 + $1.reps } - previous.reduce(0) { $0 + $1.reps }
        return L10n.text("At the same load: %@ total reps compared with last time.", difference >= 0 ? "+\(difference)" : String(difference))
    }
}
