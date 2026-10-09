import SwiftUI
import PhotosUI

struct MilestonesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var adding = false
    var body: some View {
        List {
            Section {
                Button(L10n.text("Add milestone")) { adding = true }
                Text(L10n.text("Automatic milestones reflect current source records and targets. Corrections or deletions update them; manual milestones remain your own notes.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("Milestones")) {
                if store.milestones.isEmpty { Text(L10n.text("No milestones yet.")).foregroundStyle(.secondary) }
                ForEach(store.milestones, id: \.key) { milestone in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(milestone.title).font(.headline)
                        Text(milestone.detail)
                        Text(milestone.date.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                        Text(milestone.isAutomatic ? L10n.text("Automatic milestone") : L10n.text("Manual milestone")).font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if !milestone.isAutomatic { Button(L10n.text("Delete"), role: .destructive) { store.deleteMilestone(milestone) } }
                    }
                }
            }
        }.navigationTitle(L10n.text("Milestones"))
            .sheet(isPresented: $adding) { MilestoneEditor().storeErrorBanner() }
    }
}

private struct MilestoneEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var date = Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.text("Milestone title"), text: $title)
                DatePicker(L10n.text("Date"), selection: $date, in: ...Date(), displayedComponents: .date)
                TextField(L10n.text("Notes"), text: $notes, axis: .vertical)
            }.navigationTitle(L10n.text("Add milestone"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("Save")) { if store.logMilestone(title: title, detail: notes, date: date) { dismiss() } }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 200 || notes.count > 4000)
                    }
                }
        }
    }
}

struct ProgressPhotosView: View {
    @EnvironmentObject private var store: AppStore
    @State private var angle = ProgressPhotoAngle.front
    @State private var comparison = 0
    @State private var adding = false
    var body: some View {
        let photos = store.timelinePhotos(angle: angle)
        let pair = GrowthTimeline.photoComparison(photos, angle: angle, monthsAgo: comparison == 1 ? 3 : nil,
                                                 weeksAgo: comparison == 0 ? 4 : nil, asOf: store.currentDate, calendar: .current)
        List {
            Section {
                Button(L10n.text("Add progress photo")) { adding = true }
                Text(L10n.text("Progress photos stay on this device. They are never uploaded for food recognition. iCloud backup/sync is not implemented; export an archive to keep a separate copy.")).font(.caption).foregroundStyle(.secondary)
                Picker(L10n.text("Photo angle"), selection: $angle) {
                    ForEach(ProgressPhotoAngle.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section(L10n.text("Photo comparison")) {
                Picker(L10n.text("Compare"), selection: $comparison) {
                    Text(L10n.text("This week vs 4 weeks ago")).tag(0)
                    Text(L10n.text("This month vs 3 months ago")).tag(1)
                    Text(L10n.text("Earliest vs latest")).tag(2)
                }
                if let pair {
                    HStack(alignment: .top) {
                        TimelinePhotoRow(photo: pair.earlier)
                        TimelinePhotoRow(photo: pair.later)
                    }
                } else { Text(L10n.text("No matching photo pair for this angle and period.")).font(.caption).foregroundStyle(.secondary) }
            }
            Section(L10n.text("Progress Photos")) {
                let selected = photos.filter { $0.angle == angle }.sorted { $0.date > $1.date }
                if selected.isEmpty { Text(L10n.text("No progress photos yet.")).foregroundStyle(.secondary) }
                ForEach(selected) { photo in
                    TimelinePhotoRow(photo: photo)
                        .swipeActions {
                            Button(L10n.text("Delete"), role: .destructive) {
                                if let record = store.progressPhotos.first(where: { $0.id == photo.id }) { store.deleteProgressPhoto(record) }
                            }
                        }
                }
            }
        }.navigationTitle(L10n.text("Progress Photos"))
            .sheet(isPresented: $adding) { ProgressPhotoEditor().storeErrorBanner() }
    }
}

struct TimelinePhotoRow: View {
    var photo: TimelinePhoto
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = UIImage(data: photo.data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260).accessibilityLabel(photo.angle.label)
            }
            Text(photo.angle.label).font(.headline)
            Text(photo.date.formatted(date: .abbreviated, time: .omitted)).font(.caption)
            if !photo.notes.isEmpty { Text(photo.notes).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct ProgressPhotoEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var angle = ProgressPhotoAngle.front
    @State private var notes = ""
    @State private var selection: PhotosPickerItem?
    @State private var data: Data?
    @State private var loading = false
    @State private var loadTask: Task<Void, Never>?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L10n.text("Date"), selection: $date, in: ...Date(), displayedComponents: .date)
                Picker(L10n.text("Photo angle"), selection: $angle) {
                    ForEach(ProgressPhotoAngle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                PhotosPicker(selection: $selection, matching: .images) { Label(L10n.text("Choose photo"), systemImage: "photo") }
                if let data, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 250) }
                TextField(L10n.text("Notes"), text: $notes, axis: .vertical)
                if loading { ProgressView(L10n.text("Loading photo…")) }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(loading).navigationTitle(L10n.text("Add progress photo"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { loadTask?.cancel(); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("Save")) {
                            if let data, store.logProgressPhoto(data: data, angle: angle, date: date, notes: notes) { dismiss() }
                        }.disabled(data == nil || loading || notes.count > 4000)
                    }
                }
                .onChange(of: selection) { _, selection in
                    loadTask?.cancel()
                    guard let selection else { loading = false; return }
                    loading = true; error = nil
                    loadTask = Task { @MainActor in
                        do {
                            let original = try await selection.loadTransferable(type: Data.self)
                            try Task.checkCancellation()
                            guard let original, let jpeg = MealPhoto.jpeg(original), jpeg.count <= 6 * 1024 * 1024 else {
                                loading = false; error = L10n.text("This progress photo could not be read. Choose another image."); return
                            }
                            data = jpeg
                        } catch is CancellationError { return }
                        catch { self.error = L10n.text("Could not load photo: %@", error.localizedDescription) }
                        loading = false
                    }
                }
                .onDisappear { loadTask?.cancel() }
        }
    }
}
