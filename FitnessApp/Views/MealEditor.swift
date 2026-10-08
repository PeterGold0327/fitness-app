import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import ImageIO

struct NumberField: View {
    var title: String
    @Binding var value: Double
    @Environment(\.locale) private var locale
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, text: $text)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 90, maxWidth: 140)
                    .accessibilityLabel(title)
            }
            if !value.isFinite { Text("Enter a valid number.").font(.caption).foregroundStyle(.red) }
        }
        .onAppear { syncText() }
        .onChange(of: text) { _, input in value = NumericInput.parse(input, locale: locale) ?? .nan }
        .onChange(of: value) { _, updated in
            if updated.isFinite && NumericInput.parse(text, locale: locale) != updated { syncText() }
        }
    }
    private func syncText() {
        text = value.isFinite ? value.formatted(.number.grouping(.never).precision(.fractionLength(0...6)).locale(locale)) : ""
    }
}

struct MealEditor: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var analysisSettings: FoodAnalysisSettings
    @Environment(\.dismiss) private var dismiss
    var existing: Meal? = nil
    var startWithCamera = false
    @State private var name = ""
    @State private var date = Date()
    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var analyzing = false
    @State private var loadingPhoto = false
    @State private var requestingCamera = false
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var cameraDenied = false
    @State private var saving = false
    private var busy: Bool { analyzing || loadingPhoto || requestingCamera }
    @State private var estimatedItems: [EstimatedFoodItem] = []
    @State private var analysisSource: FoodAnalysisSource = .manual
    @State private var analysisConfidence = 0.0
    @State private var analysisNotes = ""
    @State private var analysisTask: Task<Void, Never>?
    private var itemised: Bool { !estimatedItems.isEmpty }
    private var totalCalories: Double { itemised ? estimatedItems.reduce(0) { $0 + $1.calories } : calories }
    private var totalProtein: Double { itemised ? estimatedItems.reduce(0) { $0 + $1.protein } : protein }
    private var totalCarbs: Double { itemised ? estimatedItems.reduce(0) { $0 + $1.carbs } : carbs }
    private var totalFat: Double { itemised ? estimatedItems.reduce(0) { $0 + $1.fat } : fat }
    @State private var error: String?
    @State private var loaded = false
    private var valid: Bool {
        EntryValidation.meal(name: name, calories: totalCalories, protein: totalProtein, carbs: totalCarbs, fat: totalFat) &&
        estimatedItems.count <= 30 && estimatedItems.allSatisfy(\.valid) &&
        analysisConfidence.isFinite && (0...1).contains(analysisConfidence) && analysisNotes.count <= 4000
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Photo (optional)") {
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose photo", systemImage: "photo") }.disabled(busy)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { Task { await openCamera() } } label: { Label("Take photo", systemImage: "camera") }.disabled(busy)
                    } else { Text("Camera unavailable here. Choose a photo instead.").font(.caption) }
                    if loadingPhoto { ProgressView("Loading photo…") }
                    if cameraDenied {
                        Text("Camera access is disabled. You can still choose a photo or log manually.").font(.caption)
                        Button("Open iPhone Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    if photoData != nil {
                        Button(analyzing ? "Analyzing…" : analysisSettings.configuration.mode == .mock ? "Analyze with demo provider" : "Analyze food photo") {
                            analysisTask = Task { await analyze() }
                        }
                            .disabled(busy)
                        Button("Remove photo", role: .destructive) { flagPhotoChange(); photoData = nil; photoItem = nil }.disabled(busy)
                    }
                    if analysisSettings.configuration.mode == .mock {
                        Text("Demo mode returns fixed example foods and never uploads the photo.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Analyze sends this photo to \(analysisSettings.configuration.endpointURL?.host ?? "the configured provider"). Review all estimates before saving.").font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink("Configure provider & API key") { FoodAnalysisSettingsView() }.disabled(busy)
                    if analyzing { ProgressView("Waiting for food estimates…") }
                }
                Section("Meal estimate — editable") {
                    TextField("Food / meal name", text: $name)
                    DatePicker("Eaten at", selection: $date, in: ...Date())
                        .disabled(existing?.isBreakfast == true)
                    if itemised {
                        MetricRow(title: "Calories", value: "\(totalCalories.wholeText) kcal")
                        MetricRow(title: "Protein", value: "\(totalProtein.wholeText) g")
                        MetricRow(title: "Carbs", value: "\(totalCarbs.wholeText) g")
                        MetricRow(title: "Fat", value: "\(totalFat.wholeText) g")
                        Text("Totals update from the food items below. Edit each portion's calories/macros to correct the total.").font(.caption)
                    } else {
                        NumberField(title: "Calories (kcal)", value: $calories)
                        NumberField(title: "Protein (g)", value: $protein)
                        NumberField(title: "Carbs (g)", value: $carbs)
                        NumberField(title: "Fat (g)", value: $fat)
                    }
                    Text("Use the meal name for portions, e.g. chicken 150 g + cooked rice 200 g. Macros can differ from calculated energy because labels and portions vary.").font(.caption)
                }
                .disabled(busy)
                if itemised {
                    Section("Detected foods — editable") {
                        ForEach($estimatedItems) { $item in
                            DisclosureGroup {
                                FoodEstimateItemEditor(item: $item)
                                Button("Remove this food", role: .destructive) {
                                    let id = item.id
                                    estimatedItems.removeAll { $0.id == id }
                                    if estimatedItems.isEmpty { calories = 0; protein = 0; carbs = 0; fat = 0 }
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name.isEmpty ? "New food — enter details" : item.name)
                                    Text("\(item.grams.wholeText) g · \(item.calories.wholeText) kcal · \(item.protein.wholeText) g protein").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Add a missing food") {
                            estimatedItems.append(EstimatedFoodItem(name: "", grams: 0, calories: 0, protein: 0,
                                carbs: 0, fat: 0, confidence: 0, uncertaintyNotes: "Added manually; verify portion and product labels."))
                        }.disabled(estimatedItems.count >= 30)
                        Text("Values are for the whole listed portion. Changing grams does not automatically rescale macros; edit the nutrition values too.").font(.caption)
                    }.disabled(busy)
                }
                if analysisSource != .manual || !analysisNotes.isEmpty {
                    Section("Analysis — review before saving") {
                        Text(analysisSource.label).foregroundStyle(analysisSource == .mock || analysisSource == .mockFallback ? .orange : .secondary)
                        NumberField(title: "Overall confidence (0–1)", value: $analysisConfidence)
                        TextField("Uncertainty / assumptions", text: $analysisNotes, axis: .vertical)
                        Text("Confidence is an uncalibrated estimate. Check hidden oils, sauces and portion sizes. Every detected food can be edited or removed.").font(.caption)
                    }.disabled(busy)
                }
                if !name.isEmpty && !valid {
                    Section { Text("Check names and finite values: positive item grams (up to 10,000), nonnegative calories/macros, confidence 0–1 and notes up to 4,000 characters. Zero-calorie drinks can be logged.").font(.caption).foregroundStyle(.red) }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle(existing == nil ? "Log food" : "Edit meal").keyboardDoneButton()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { analysisTask?.cancel(); photoLoadTask?.cancel(); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid || busy || saving) }
                }
                .interactiveDismissDisabled(loadingPhoto || requestingCamera)
                .task {
                    guard !loaded else { return }; loaded = true
                    if let existing {
                        name = existing.name; date = existing.date; calories = existing.calories
                        protein = existing.protein; carbs = existing.carbs; fat = existing.fat; photoData = existing.photoData
                        analysisSource = FoodAnalysisSource(rawValue: existing.analysisSource) ?? .manual
                        analysisConfidence = existing.analysisConfidence ?? 0
                        analysisNotes = existing.analysisNotes
                        // Legacy/recipe children without full analysis metadata remain aggregate edits.
                        if existing.foods.allSatisfy({ $0.confidence != nil }) {
                            estimatedItems = existing.foods.sorted { $0.position < $1.position }.map {
                                EstimatedFoodItem(name: $0.name, grams: $0.grams, calories: $0.calories, protein: $0.protein,
                                    carbs: $0.carbs, fat: $0.fat, confidence: $0.confidence ?? 0, uncertaintyNotes: $0.uncertaintyNotes)
                            }
                        }
                    } else if startWithCamera { await openCamera() }
                }
                .onChange(of: photoItem) { _, item in
                    photoLoadTask?.cancel()
                    guard let item else { loadingPhoto = false; return }
                    loadingPhoto = true; error = nil
                    photoLoadTask = Task { @MainActor in
                        do {
                            let data = try await item.loadTransferable(type: Data.self)
                            guard !Task.isCancelled else { return }
                            if let data, let normalized = MealPhoto.jpeg(data) {
                                flagPhotoChange(); photoData = normalized
                            } else { error = "This photo could not be read. Choose another image or log the meal manually." }
                        } catch {
                            guard !Task.isCancelled else { return }
                            self.error = "Could not load photo: \(error.localizedDescription)"
                        }
                        loadingPhoto = false
                    }
                }
                .onDisappear { photoLoadTask?.cancel(); analysisTask?.cancel() }
                .sheet(isPresented: $showCamera) {
                    CameraPicker { image in
                        if let data = image.resizedForMeal()?.jpegData(compressionQuality: 0.8) { flagPhotoChange(); photoData = data }
                        else { error = "Could not save the photo. Try again or log manually." }
                    }
                }
        }
    }
    @MainActor private func openCamera() async {
        guard !busy, UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        requestingCamera = true
        defer { requestingCamera = false }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let allowed: Bool
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        else { allowed = status == .authorized }
        cameraDenied = !allowed
        if allowed { showCamera = true }
    }
    @MainActor private func analyze() async {
        guard !busy, let data = photoData else { return }
        analyzing = true; error = nil
        defer { analyzing = false }
        do {
            let analyzer = try analysisSettings.analyzer()
            let estimate = try await analyzer.analyze(imageData: data)
            try Task.checkCancellation()
            name = estimate.name; calories = estimate.calories; protein = estimate.protein
            carbs = estimate.carbs; fat = estimate.fat; estimatedItems = estimate.items
            analysisSource = estimate.source; analysisConfidence = estimate.confidence; analysisNotes = estimate.uncertaintyNotes
        } catch is CancellationError { return }
        catch { self.error = "Analysis failed: \(error.localizedDescription). You can still enter the meal manually." }
    }
    private func flagPhotoChange() {
        guard analysisSource != .manual && photoData != nil else { return }
        analysisNotes = "Photo changed/removed. Previous estimates are retained; verify them or analyze the new photo.\n" + String(analysisNotes.prefix(3700))
    }
    private func save() {
        guard valid, !busy, !saving else { return }; saving = true
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let success: Bool
        if let existing {
            success = store.updateMeal(existing, name: cleanName, date: date, calories: totalCalories,
                protein: totalProtein, carbs: totalCarbs, fat: totalFat, photoData: photoData,
                estimatedItems: estimatedItems, source: analysisSource, confidence: analysisSource == .manual ? nil : analysisConfidence,
                notes: analysisNotes)
        } else {
            let meal = Meal(date: date, name: cleanName, calories: totalCalories, protein: totalProtein,
                            carbs: totalCarbs, fat: totalFat, photoData: photoData)
            meal.analysisSource = analysisSource.rawValue
            meal.analysisConfidence = analysisSource == .manual ? nil : analysisConfidence
            meal.analysisNotes = analysisNotes
            meal.foods = estimatedItems.enumerated().map { position, item in
                let food = FoodItem(name: item.name, grams: item.grams, calories: item.calories, protein: item.protein,
                    carbs: item.carbs, fat: item.fat, confidence: item.confidence, uncertaintyNotes: item.uncertaintyNotes)
                food.position = position; return food
            }
            success = store.logMeal(meal)
        }
        if success { dismiss() } else { saving = false }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onPhoto: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera; controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

extension UIImage {
    func resizedForMeal() -> UIImage? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, 1400 / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

private enum MealPhoto {
    /// Downsample library images before full decode to avoid large-image memory spikes.
    static func jpeg(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1400
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }
}

private struct FoodEstimateItemEditor: View {
    @Binding var item: EstimatedFoodItem
    var body: some View {
        TextField("Detected food name", text: $item.name)
        NumberField(title: "Estimated grams", value: $item.grams)
        NumberField(title: "Item calories (kcal)", value: $item.calories)
        NumberField(title: "Item protein (g)", value: $item.protein)
        NumberField(title: "Item carbs (g)", value: $item.carbs)
        NumberField(title: "Item fat (g)", value: $item.fat)
        NumberField(title: "Item confidence (0–1)", value: $item.confidence)
        TextField("Item uncertainty / assumptions", text: $item.uncertaintyNotes, axis: .vertical)
    }
}
