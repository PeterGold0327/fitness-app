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
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer()
                TextField(title, text: $text)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 90, maxWidth: 140)
                    .accessibilityLabel(title)
            }
            if !value.isFinite { Text(L10n.text("Enter a valid number.")).font(.caption).foregroundStyle(.red) }
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
    @State private var mealCategory = ""
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
    @State private var mealContext = ""
    @State private var awaitingNutrition = false
    @State private var hasFoodReview = false
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
                photoSection
                mealEstimateSection.disabled(busy)
                if itemised || hasFoodReview {
                    detectedFoodsSection
                }
                if analysisSource != .manual || !analysisNotes.isEmpty {
                    analysisSection
                }
                if !name.isEmpty && !valid {
                    Section { Text(L10n.text("Check names and finite values: positive item grams (up to 10,000), nonnegative calories/macros, confidence 0–1 and notes up to 4,000 characters. Zero-calorie drinks can be logged.")).font(.caption).foregroundStyle(.red) }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle(existing == nil ? L10n.text("Log food") : L10n.text("Edit meal")).keyboardDoneButton()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { analysisTask?.cancel(); photoLoadTask?.cancel(); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Save")) { save() }.disabled(!valid || busy || saving || awaitingNutrition) }
                }
                .interactiveDismissDisabled(loadingPhoto || requestingCamera)
                .task {
                    guard !loaded else { return }; loaded = true
                    if let existing {
                        mealCategory = existing.mealCategory
                        name = existing.name; date = existing.date; calories = existing.calories
                        protein = existing.protein; carbs = existing.carbs; fat = existing.fat; photoData = existing.photoData
                        analysisSource = FoodAnalysisSource(rawValue: existing.analysisSource) ?? .manual
                        analysisConfidence = existing.analysisConfidence ?? 0
                        analysisNotes = existing.analysisNotes
                        // Legacy/recipe children without full analysis metadata remain aggregate edits.
                        if existing.foods.allSatisfy({ $0.confidence != nil }) {
                            hasFoodReview = !existing.foods.isEmpty
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
                            } else { error = L10n.text("This photo could not be read. Choose another image or log the meal manually.") }
                        } catch {
                            guard !Task.isCancelled else { return }
                            self.error = L10n.text("Could not load photo: %@", String(describing: error.localizedDescription))
                        }
                        loadingPhoto = false
                    }
                }
                .onDisappear { photoLoadTask?.cancel(); analysisTask?.cancel() }
                .sheet(isPresented: $showCamera) {
                    CameraPicker { image in
                        if let data = image.resizedForMeal()?.jpegData(compressionQuality: 0.8) { flagPhotoChange(); photoData = data }
                        else { error = L10n.text("Could not save the photo. Try again or log manually.") }
                    }
                }
        }
    }

    private var analysisSection: some View {
        Section(L10n.text("Analysis — review before saving")) {
            Text(analysisSource.label).foregroundStyle(analysisSource == .mock || analysisSource == .mockFallback ? Color.orange : Color.secondary)
            NumberField(title: L10n.text("Overall confidence (0–1)"), value: $analysisConfidence)
            TextField(L10n.text("Uncertainty / assumptions"), text: $analysisNotes, axis: .vertical)
            Text(L10n.text("Confidence is an uncalibrated estimate. Check hidden oils, sauces and portion sizes. Every detected food can be edited or removed.")).font(.caption)
        }.disabled(busy)
    }

    private var detectedFoodsSection: some View {
        Section(L10n.text("Detected foods — editable")) {
            ForEach($estimatedItems) { $item in
                DisclosureGroup {
                    FoodEstimateItemEditor(item: $item, nameChanged: {
                        if photoData != nil { awaitingNutrition = true }
                    })
                    Button(L10n.text("Remove this food"), role: .destructive) {
                        let id = item.id
                        estimatedItems.removeAll { $0.id == id }
                        if estimatedItems.isEmpty { calories = 0; protein = 0; carbs = 0; fat = 0 }
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.confidenceLevel).font(.caption).foregroundStyle(.secondary)
                        Text(item.name.isEmpty ? L10n.text("New food — enter details") : item.name)
                        if awaitingNutrition {
                            Text(L10n.text("%@ g · nutrition awaiting review", String(describing: item.grams.wholeText))).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(L10n.text("%@ g · %@ kcal · %@ g protein", String(describing: item.grams.wholeText), String(describing: item.calories.wholeText), String(describing: item.protein.wholeText))).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button(L10n.text("Add a missing food")) {
                if photoData != nil { awaitingNutrition = true }
                estimatedItems.append(EstimatedFoodItem(name: "", grams: 0, calories: 0, protein: 0,
                    carbs: 0, fat: 0, confidence: 0, uncertaintyNotes: L10n.text("Added manually; verify portion and product labels.")))
            }.disabled(estimatedItems.count >= 30)
            if awaitingNutrition {
                Button(L10n.text("Use my manually corrected nutrition")) {
                    awaitingNutrition = false; analysisSource = .manual
                }.disabled(!valid || estimatedItems.isEmpty)
            }
            Text(L10n.text("Changing grams rescales the current nutrition estimate. Correct names or ingredients, then estimate nutrition again; check oils and sauces.")).font(.caption)
        }.disabled(busy)
    }

    private var mealEstimateSection: some View {
        Section(L10n.text("Meal estimate — editable")) {
            TextField(L10n.text("Food / meal name"), text: $name)
            Picker(L10n.text("Meal category"), selection: $mealCategory) {
                Text(L10n.text("Automatic (by time)")).tag("")
                ForEach(TimelineMealCategory.allCases, id: \.rawValue) { category in
                    Text(category.label).tag(category.rawValue)
                }
            }.disabled(existing?.isBreakfast == true)
            DatePicker(L10n.text("Eaten at"), selection: $date, in: ...Date())
                .disabled(existing?.isBreakfast == true)
            if awaitingNutrition {
                Text(L10n.text("Step 1: review detected dishes and portions, then estimate nutrition. Nothing is saved yet.")).font(.callout)
            } else if itemised {
                MetricRow(title: L10n.text("Calories"), value: L10n.text("%@ kcal", String(describing: totalCalories.wholeText)))
                MetricRow(title: L10n.text("Protein"), value: L10n.text("%@ g", String(describing: totalProtein.wholeText)))
                MetricRow(title: L10n.text("Carbs"), value: L10n.text("%@ g", String(describing: totalCarbs.wholeText)))
                MetricRow(title: L10n.text("Fat"), value: L10n.text("%@ g", String(describing: totalFat.wholeText)))
                Text(L10n.text("Totals update from the food items below. Edit each portion's calories/macros to correct the total.")).font(.caption)
            } else {
                NumberField(title: L10n.text("Calories (kcal)"), value: $calories)
                NumberField(title: L10n.text("Protein (g)"), value: $protein)
                NumberField(title: L10n.text("Carbs (g)"), value: $carbs)
                NumberField(title: L10n.text("Fat (g)"), value: $fat)
            }
            Text(L10n.text("Use the meal name for portions, e.g. chicken 150 g + cooked rice 200 g. Macros can differ from calculated energy because labels and portions vary.")).font(.caption)
        }
    }

    private var photoSection: some View {
        Section(L10n.text("Photo (optional)")) {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
            }
            PhotosPicker(selection: $photoItem, matching: .images) { Label(L10n.text("Choose photo"), systemImage: "photo") }.disabled(busy)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { Task { await openCamera() } } label: { Label(L10n.text("Take photo"), systemImage: "camera") }.disabled(busy)
            } else { Text(L10n.text("Camera unavailable here. Choose a photo instead.")).font(.caption) }
            if loadingPhoto { ProgressView(L10n.text("Loading photo…")) }
            if cameraDenied {
                Text(L10n.text("Camera access is disabled. You can still choose a photo or log manually.")).font(.caption)
                Button(L10n.text("Open iPhone Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            if photoData != nil {
                TextField(L10n.text("Meal context: dishes, ingredients, oil, portions…"), text: $mealContext, axis: .vertical)
                    .disabled(busy)
                Text(L10n.text("For example: 宫保鸡丁 + 米饭；少油，米饭熟重 150 g；麻辣烫不喝汤。Context is sent with the photo only when you request analysis.")).font(.caption)
                if mealContext.count > 2000 {
                    Text(L10n.text("Keep meal context within 2,000 characters.")).foregroundStyle(.red)
                }
                if hasFoodReview || itemised {
                    Button(L10n.text("Step 2: estimate nutrition for reviewed foods")) {
                        analysisTask = Task { await analyze(nutrition: true) }
                    }.disabled(busy || !valid || estimatedItems.isEmpty || mealContext.count > 2000)
                    Text(L10n.text("Re-analyzing the photo replaces the current food list after success. Estimating nutrition keeps your reviewed names and portions.")).font(.caption)
                }
                Button(analyzing ? L10n.text("Analyzing…") : analysisSettings.configuration.mode == .mock ? L10n.text("Analyze with demo provider") : L10n.text("Step 1: detect / re-analyze foods")) {
                    analysisTask = Task { await analyze() }
                }
                    .disabled(busy || mealContext.count > 2000)
                if analyzing {
                    Button(L10n.text("Cancel analysis")) { analysisTask?.cancel() }
                }
                Button(L10n.text("Remove photo"), role: .destructive) { flagPhotoChange(); photoData = nil; photoItem = nil }.disabled(busy)
            }
            if analysisSettings.configuration.mode == .mock {
                Text(L10n.text("Demo mode returns fixed example foods and never uploads the photo.")).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L10n.text("Analyze sends this photo to %@. Review all estimates before saving.", String(describing: analysisSettings.configuration.endpointURL?.host ?? L10n.text("the configured provider")))).font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink(L10n.text("Configure provider & API key")) { FoodAnalysisSettingsView() }.disabled(busy)
            if analyzing { ProgressView(L10n.text("Waiting for food estimates…")) }
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
    @MainActor private func analyze(nutrition: Bool = false) async {
        guard !busy, let data = photoData else { return }
        analyzing = true; error = nil
        defer { analyzing = false }
        do {
            let analyzer = try analysisSettings.analyzer()
            let reviewed = FoodEstimate(name: name, items: estimatedItems, confidence: analysisConfidence,
                                        uncertaintyNotes: analysisNotes, source: analysisSource)
            let estimate: FoodEstimate
            if nutrition {
                estimate = try await analyzer.estimateNutrition(imageData: data, reviewed: reviewed, context: mealContext)
            } else {
                estimate = try await analyzer.detect(imageData: data, context: mealContext)
            }
            try Task.checkCancellation()
            name = estimate.name; calories = estimate.calories; protein = estimate.protein
            carbs = estimate.carbs; fat = estimate.fat; estimatedItems = estimate.items
            analysisSource = estimate.source; analysisConfidence = estimate.confidence; analysisNotes = estimate.uncertaintyNotes
            hasFoodReview = true; awaitingNutrition = !nutrition
        } catch is CancellationError { return }
        catch { self.error = L10n.text("Analysis failed: %@. You can still enter the meal manually.", String(describing: error.localizedDescription)) }
    }
    private func flagPhotoChange() {
        guard analysisSource != .manual && photoData != nil else { return }
        analysisNotes = L10n.text("Photo changed/removed. Previous estimates are retained; verify them or analyze the new photo.\n") + String(analysisNotes.prefix(3700))
    }
    private func save() {
        guard valid, !busy, !saving, !awaitingNutrition else { return }; saving = true
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let success: Bool
        if let existing {
            success = store.updateMeal(existing, name: cleanName, date: date, calories: totalCalories,
                protein: totalProtein, carbs: totalCarbs, fat: totalFat, photoData: photoData,
                estimatedItems: estimatedItems, source: analysisSource, confidence: analysisSource == .manual ? nil : analysisConfidence,
                notes: analysisNotes, category: mealCategory)
        } else {
            let meal = Meal(date: date, name: cleanName, calories: totalCalories, protein: totalProtein,
                            carbs: totalCarbs, fat: totalFat, photoData: photoData)
            meal.mealCategory = mealCategory
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

enum MealPhoto {
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
    var nameChanged: () -> Void
    @State private var lastValidGrams = 0.0
    private var portion: Binding<Double> {
        Binding(get: { item.grams }, set: { grams in
            // NumberField can emit invalid intermediate text while the user types.
            // Keep the last usable density so clearing/retyping a portion does not lose it.
            if !item.grams.isFinite || item.grams <= 0 || item.grams > 10000 {
                item.grams = lastValidGrams
            }
            item.resize(to: grams)
            if grams.isFinite, grams > 0, grams <= 10000 { lastValidGrams = grams }
        })
    }
    var body: some View {
        TextField(L10n.text("Detected food name"), text: $item.name)
            .onChange(of: item.name) { _, _ in nameChanged() }
        NumberField(title: L10n.text("Estimated grams"), value: portion)
            .onAppear { lastValidGrams = item.grams }
            .onChange(of: item.grams) { _, grams in
                if grams.isFinite, grams > 0, grams <= 10000 { lastValidGrams = grams }
            }
        Text(item.confidenceLevel).font(.caption)
        NumberField(title: L10n.text("Item calories (kcal)"), value: $item.calories)
        NumberField(title: L10n.text("Item protein (g)"), value: $item.protein)
        NumberField(title: L10n.text("Item carbs (g)"), value: $item.carbs)
        NumberField(title: L10n.text("Item fat (g)"), value: $item.fat)
        NumberField(title: L10n.text("Item confidence (0–1)"), value: $item.confidence)
        TextField(L10n.text("Item uncertainty / assumptions"), text: $item.uncertaintyNotes, axis: .vertical)
    }
}
