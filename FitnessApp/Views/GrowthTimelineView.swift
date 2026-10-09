import SwiftUI
import Charts
import UniformTypeIdentifiers

struct ProgressViewScreen: View {
    @Binding var sheet: AppSheet?
    var body: some View {
        List {
            Section(L10n.text("Progress")) {
                NavigationLink { ProgressOverviewView(sheet: $sheet) } label: {
                    Label(L10n.text("Overview"), systemImage: "chart.xyaxis.line")
                }
                NavigationLink { GrowthTimelineView() } label: {
                    Label(L10n.text("Growth Timeline"), systemImage: "calendar")
                }
                NavigationLink { MilestonesView() } label: {
                    Label(L10n.text("Milestones"), systemImage: "flag")
                }
                NavigationLink { ProgressPhotosView() } label: {
                    Label(L10n.text("Progress Photos"), systemImage: "photo.on.rectangle")
                }
            }
            Section {
                Text(L10n.text("Your private history, assembled from existing logs. No duplicate meals, workouts, weights or sleep records.")).font(.callout).foregroundStyle(.secondary)
            }
        }.navigationTitle(L10n.text("Progress"))
    }
}

struct GrowthTimelineView: View {
    @EnvironmentObject private var store: AppStore
    @State private var period = TimelinePeriod.day
    @State private var selectedDate = Date()
    @AppStorage("timelineOnThisDay") private var showOnThisDay = true
    @State private var showExport = false
    private var calendar: Calendar { .current }
    private var interval: DateInterval { period.interval(containing: selectedDate, calendar: calendar) }
    var body: some View {
        let history = store.makeTimelineHistory(includePhotoData: period == .day, photoInterval: interval)
        let summary = GrowthTimeline.summary(history: history, interval: interval, calendar: calendar, asOf: store.currentDate)
        List {
            Section {
                Picker(L10n.text("Browse history"), selection: $period) {
                    ForEach(TimelinePeriod.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                DatePicker(L10n.text("Date"), selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                HStack {
                    Button { move(-1) } label: { Label(L10n.text("Previous period"), systemImage: "chevron.left") }
                    Spacer()
                    Button { move(1) } label: { Label(L10n.text("Next period"), systemImage: "chevron.right") }
                        .disabled(interval.end > store.currentDate)
                }.buttonStyle(.borderless)
                Text(L10n.text("Legacy meal categories are inferred by time. Correct a meal's category in its editor when needed.")).font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Export Archive")) { showExport = true }
            }
            if period != .day {
                TimelineSummarySection(summary: summary)
                if period == .month || period == .year {
                    let previousDate = calendar.date(byAdding: period.component, value: -1, to: interval.start)!
                    let previous = GrowthTimeline.summary(history: history, interval: period.interval(containing: previousDate, calendar: calendar), calendar: calendar, asOf: store.currentDate)
                    Section(L10n.text("Previous period comparison")) {
                        Text(summary.comparison(with: previous)).font(.callout)
                        Text(L10n.text("Both targets: %@/%@ logged days, versus %@/%@ in the previous period.", String(summary.jointlyAdherentDays), String(summary.nutritionDays), String(previous.jointlyAdherentDays), String(previous.nutritionDays))).font(.caption)
                        ForEach(Array(summary.exerciseComparisons(with: previous).enumerated()), id: \.offset) { _, comparison in Text(comparison).font(.caption) }
                    }
                }
                TimelineTrendsSection(days: summary.days)
                Section(L10n.text("Recorded days")) {
                    if summary.days.isEmpty { Text(L10n.text("No records in this period.")).foregroundStyle(.secondary) }
                    ForEach(summary.days.reversed()) { day in
                        NavigationLink { TimelineDayView(day: day) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                                Text(day.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                TimelineDaySections(day: GrowthTimeline.day(selectedDate, history: history, calendar: calendar, asOf: store.currentDate))
            }
            Section {
                Toggle(L10n.text("On This Day"), isOn: $showOnThisDay)
                if showOnThisDay {
                    let historical = GrowthTimeline.onThisDay(history: history, date: selectedDate, calendar: calendar)
                    if historical.isEmpty { Text(L10n.text("No earlier anniversary records yet.")).font(.caption).foregroundStyle(.secondary) }
                    ForEach(historical) { day in
                        NavigationLink { TimelineAnniversaryView(historical: day, current: GrowthTimeline.day(selectedDate, history: history, calendar: calendar, asOf: store.currentDate)) } label: {
                            VStack(alignment: .leading) {
                                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                Text(day.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.navigationTitle(L10n.text("Growth Timeline"))
            .sheet(isPresented: $showExport) { TimelineExportView(selectedDate: selectedDate, period: period).storeErrorBanner() }
    }
    private func move(_ amount: Int) {
        if let date = calendar.date(byAdding: period.component, value: amount, to: interval.start) { selectedDate = min(date, store.currentDate) }
    }
}

private struct TimelineSummarySection: View {
    var summary: TimelineSummary
    var body: some View {
        Section(L10n.text("Period summary")) {
            Text(summary.text)
            MetricRow(title: L10n.text("Starting weight"), value: weight(summary.startingWeight))
            MetricRow(title: L10n.text("Ending weight"), value: weight(summary.endingWeight))
            MetricRow(title: L10n.text("Average weight (available weigh-ins)"), value: weight(summary.averageWeight))
            MetricRow(title: L10n.text("Calorie target adherence"), value: "\(summary.calorieAdherentDays)/\(summary.nutritionDays)")
            MetricRow(title: L10n.text("Protein target adherence"), value: "\(summary.proteinAdherentDays)/\(summary.nutritionDays)")
            Text(L10n.text("Calories within ±10% of current target; protein at or above current target. Partial logs are not proof of complete intake.")).font(.caption).foregroundStyle(.secondary)
        }
        if !summary.exercises.isEmpty {
            Section(L10n.text("Exercise progression")) {
                ForEach(summary.exercises) { Text($0.summary).font(.callout) }
                Text(L10n.text("Best compares load × reps per completed set, not total volume or predicted strength. Bodyweight rows compare reps.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func weight(_ value: Double?) -> String { value.map { L10n.text("%@ kg", GrowthTimeline.number($0)) } ?? L10n.text("—") }
}

private struct TimelineTrendsSection: View {
    var days: [TimelineDay]
    var body: some View {
        if days.contains(where: { $0.weight != nil }) {
            Section(L10n.text("Weight trend")) {
                Chart(days) { day in
                    if let weight = day.weight { PointMark(x: .value(L10n.text("Date"), day.date), y: .value(L10n.text("Weight"), weight)) }
                    if let average = day.weightAverage { LineMark(x: .value(L10n.text("Date"), day.date), y: .value(L10n.text("7-day average"), average)) }
                }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 180)
            }
        }
        if days.contains(where: { $0.sleep != nil }) {
            Section(L10n.text("Sleep trend")) {
                Chart(days) { day in
                    if let sleep = day.sleep { BarMark(x: .value(L10n.text("Date"), day.date), y: .value(L10n.text("Sleep (h)"), sleep)) }
                }.frame(height: 150)
            }
        }
    }
}

struct TimelineDayView: View {
    @EnvironmentObject private var store: AppStore
    var day: TimelineDay
    var body: some View {
        // Resolve again from canonical records so edits/deletions are reflected on return.
        List { TimelineDaySections(day: GrowthTimeline.day(day.date, history: store.makeTimelineHistory(photoInterval: TimelinePeriod.day.interval(containing: day.date, calendar: .current)), calendar: .current, asOf: store.currentDate)) }
            .navigationTitle(day.date.formatted(date: .abbreviated, time: .omitted))
    }
}

private struct TimelineDaySections: View {
    var day: TimelineDay
    var body: some View {
        if !day.hasRecords {
            Section { Text(L10n.text("No records in this period.")).foregroundStyle(.secondary) }
        } else {
            Section(L10n.text("Body")) {
                MetricRow(title: L10n.text("Weight"), value: day.weight.map { L10n.text("%@ kg", GrowthTimeline.number($0)) } ?? L10n.text("Not logged"))
                if let average = day.weightAverage {
                    Text(L10n.text("7-day average: %@ kg (%@ weigh-ins)", GrowthTimeline.number(average), String(day.weightSampleCount)))
                }
            }
            Section(L10n.text("Sleep")) {
                Text(day.sleep.map { L10n.text("%@ h", GrowthTimeline.number($0)) } ?? L10n.text("No readable Health sleep"))
            }
            Section(L10n.text("Nutrition")) {
                if day.meals.isEmpty { Text(L10n.text("Not logged")) }
                ForEach(day.meals) { meal in TimelineMealRow(meal: meal) }
                if !day.meals.isEmpty {
                    Text(L10n.text("Daily totals: %@ kcal · %@ g protein · %@ g carbs · %@ g fat", GrowthTimeline.number(day.calories), GrowthTimeline.number(day.protein), GrowthTimeline.number(day.carbs), GrowthTimeline.number(day.fat))).font(.headline)
                }
            }
            Section(L10n.text("Gym")) {
                if day.workouts.isEmpty { Text(L10n.text("None logged")) }
                ForEach(day.workouts) { workout in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(workout.name).font(.headline)
                        ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, exercise in
                            Text(L10n.text("%@: %@ kg · %@ sets × %@ reps · RPE %@", exercise.name, GrowthTimeline.number(exercise.weight), String(exercise.sets), String(exercise.reps), GrowthTimeline.number(exercise.rpe)))
                            if !exercise.notes.isEmpty { Text(exercise.notes).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section(L10n.text("Badminton")) { Text(day.badminton ? L10n.text("Badminton logged") : L10n.text("None logged")) }
            if !day.photos.isEmpty {
                Section(L10n.text("Progress Photos")) { ForEach(day.photos) { TimelinePhotoRow(photo: $0) } }
            }
            if !day.milestones.isEmpty {
                Section(L10n.text("Milestones")) {
                    ForEach(day.milestones) { milestone in
                        VStack(alignment: .leading) { Text(milestone.title).font(.headline); Text(milestone.detail).font(.caption) }
                    }
                }
            }
            Section(L10n.text("Daily Summary")) { Text(day.summary) }
        }
    }
}

private struct TimelineMealRow: View {
    var meal: TimelineMeal
    var body: some View {
        DisclosureGroup {
            if let data = meal.photo, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel(L10n.text("Meal photo"))
            }
            ForEach(Array(meal.foods.enumerated()), id: \.offset) { _, food in
                VStack(alignment: .leading) {
                    Text(L10n.text("%@ · %@ g", food.name, GrowthTimeline.number(food.grams)))
                    Text(L10n.text("Calories: %@ kcal · Protein: %@ g · Carbs: %@ g · Fat: %@ g", GrowthTimeline.number(food.calories), GrowthTimeline.number(food.protein), GrowthTimeline.number(food.carbs), GrowthTimeline.number(food.fat))).font(.caption)
                    if let confidence = food.confidence { Text(L10n.text("Confidence: %@", GrowthTimeline.number(confidence))).font(.caption) }
                    if !food.notes.isEmpty { Text(food.notes).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Text(L10n.text("Calories: %@ kcal · Protein: %@ g · Carbs: %@ g · Fat: %@ g", GrowthTimeline.number(meal.calories), GrowthTimeline.number(meal.protein), GrowthTimeline.number(meal.carbs), GrowthTimeline.number(meal.fat))).font(.caption)
        } label: {
            VStack(alignment: .leading) {
                Text(meal.category.label + " · " + meal.name).font(.headline)
                Text(meal.date.formatted(date: .omitted, time: .shortened)).font(.caption)
                if meal.photo != nil { Label(L10n.text("Meal photo"), systemImage: "photo").font(.caption) }
            }
        }
    }
}

private struct TimelineAnniversaryView: View {
    @EnvironmentObject private var store: AppStore
    var historical: TimelineDay; var current: TimelineDay
    var body: some View {
        let historical = GrowthTimeline.day(self.historical.date, history: store.makeTimelineHistory(photoInterval: TimelinePeriod.day.interval(containing: self.historical.date, calendar: .current)), calendar: .current, asOf: store.currentDate)
        let current = GrowthTimeline.day(self.current.date, history: store.makeTimelineHistory(photoInterval: TimelinePeriod.day.interval(containing: self.current.date, calendar: .current)), calendar: .current, asOf: store.currentDate)
        List {
            Section(L10n.text("Historical comparison")) {
                MetricRow(title: L10n.text("Historical weight"), value: historical.weight.map { L10n.text("%@ kg", GrowthTimeline.number($0)) } ?? L10n.text("Not logged"))
                MetricRow(title: L10n.text("Current weight"), value: current.weight.map { L10n.text("%@ kg", GrowthTimeline.number($0)) } ?? L10n.text("Not logged"))
                Text(historical.summary)
                Text(current.summary)
            }
            Section(L10n.text("Current gym performance")) {
                ForEach(current.workouts) { workout in
                    Text(workout.name).font(.headline)
                    ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, row in
                        Text(L10n.text("%@: %@ kg · %@ sets × %@ reps · RPE %@", row.name, GrowthTimeline.number(row.weight), String(row.sets), String(row.reps), GrowthTimeline.number(row.rpe)))
                    }
                }
                if current.workouts.isEmpty { Text(L10n.text("None logged")) }
            }
            if !current.photos.isEmpty || current.meals.contains(where: { $0.photo != nil }) {
                Section(L10n.text("Current photos")) {
                    ForEach(current.photos) { TimelinePhotoRow(photo: $0) }
                    ForEach(current.meals.filter { $0.photo != nil }) { TimelineMealRow(meal: $0) }
                }
            }
            TimelineDaySections(day: historical)
        }.navigationTitle(L10n.text("On This Day"))
    }
}

struct TimelineArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct TimelineExportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var selectedDate: Date
    @State var period: TimelinePeriod
    @State private var entireHistory = false
    @State private var includePhotos = true
    @State private var preparing = false
    @State private var exportTask: Task<Void, Never>?
    @State private var document: TimelineArchiveDocument?
    @State private var showFileExporter = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Toggle(L10n.text("Entire history"), isOn: $entireHistory)
                if !entireHistory {
                    Picker(L10n.text("Export period"), selection: $period) {
                        ForEach(TimelinePeriod.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                }
                Toggle(L10n.text("Include photos"), isOn: $includePhotos)
                Text(L10n.text("Save a ZIP to Files containing archive.md and a photos folder. Photos stay private unless you move or share the exported archive yourself.")).font(.caption)
                Button(L10n.text("Export Archive")) { prepare() }.disabled(preparing)
                if preparing { ProgressView(L10n.text("Preparing archive…")) }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(preparing).navigationTitle(L10n.text("Export Archive"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Close")) { exportTask?.cancel(); dismiss() } } }
                .fileExporter(isPresented: $showFileExporter, document: document, contentType: .zip, defaultFilename: "growth-timeline-" + GrowthTimeline.dateKey(selectedDate, calendar: .current)) { result in
                    if case .failure(let failure) = result { error = L10n.text("Export failed: %@", failure.localizedDescription) }
                    document = nil
                }
                .onDisappear { exportTask?.cancel() }
        }
    }
    private func prepare() {
        preparing = true; error = nil
        let interval = entireHistory ? nil : period.interval(containing: selectedDate, calendar: .current)
        var history = store.makeTimelineHistory(includePhotoData: includePhotos, photoInterval: interval)
        if !includePhotos {
            history.photos = []
            for index in history.meals.indices { history.meals[index].photo = nil }
        }
        let snapshot = history, calendar = Calendar.current, asOf = store.currentDate
        exportTask = Task { @MainActor in
            defer { preparing = false }
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try TimelineMarkdown.generate(history: snapshot, interval: interval, calendar: calendar, asOf: asOf).zipData()
                }
                let data = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                document = TimelineArchiveDocument(data: data); showFileExporter = true
            } catch is CancellationError { return }
            catch { self.error = L10n.text("Export failed: %@", error.localizedDescription) }
        }
    }
}
