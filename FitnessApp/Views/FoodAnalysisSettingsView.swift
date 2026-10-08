import SwiftUI

struct FoodAnalysisSettingsView: View {
    @EnvironmentObject private var settings: FoodAnalysisSettings
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FoodAnalysisConfiguration()
    @State private var newKey = ""
    @State private var hasSavedKey = false
    @State private var loaded = false
    var body: some View {
        Form {
            providerSection
            if draft.mode != .mock {
                credentialSection
                fallbackSection
                uploadSection
            }
            if let message = settings.message { Section { Text(message).foregroundStyle(.red) } }
            if !draft.valid { Section { Text("Use a valid HTTPS API URL without user info, query, fragment or a nonstandard port, and a nonempty model ID.").foregroundStyle(.red) } }
        }.navigationTitle("Food photo analysis").keyboardDoneButton()
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if settings.save(draft, newKey: newKey) { newKey = ""; dismiss() } }.disabled(!draft.valid)
            } }
            .task {
                guard !loaded else { return }; loaded = true
                draft = settings.configuration; refreshKeyStatus()
            }
            .onChange(of: draft.mode) { _, _ in newKey = ""; refreshKeyStatus() }
            .onChange(of: draft.customEndpoint) { _, _ in newKey = ""; refreshKeyStatus() }
            .onDisappear { newKey = "" }
    }

    private var uploadSection: some View {
        Section("Photo upload") {
            Text("Tapping Analyze uploads that photo to \(draft.endpointURL?.host ?? "the configured provider"). Nothing uploads when you select/capture a photo. Calls may incur your provider's API charges.")
            Text("OpenAI requests set store=false. Provider processing and retention policies still apply. No photo/request/key is written to debug logs.").font(.caption)
        }
    }

    private var fallbackSection: some View {
        Section("When the API fails") {
            Toggle("Allow labelled demo fallback", isOn: $draft.allowDemoFallback)
            Text(draft.allowDemoFallback
                ? "Development/testing only. A failed API call may show fixed demo items, clearly labelled as fallback. Verify or replace every value."
                : "Your existing draft stays intact. Retry, switch to demo mode, or enter the meal manually. No automatic fake result.").font(.caption)
        }
    }

    private var credentialSection: some View {
        Section("API credential") {
            Text(hasSavedKey ? "A key is stored for this exact endpoint." : "No key is stored for this endpoint.")
            SecureField(hasSavedKey ? "Replacement API key (optional)" : "API key", text: $newKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            Text("Keys are saved in this iPhone's Keychain, not source files or the nutrition database. Leaving the field empty keeps the stored key. A changed endpoint needs its own key.").font(.caption)
            if hasSavedKey {
                Button("Remove stored key", role: .destructive) {
                    if settings.removeKey(for: draft) { newKey = ""; refreshKeyStatus() }
                }
            }
        }
    }

    private var providerSection: some View {
        Section("Analysis provider") {
            Picker("Provider", selection: $draft.mode) {
                ForEach(FoodAnalysisMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if draft.mode == .mock {
                Text("Demo mode never uploads a photo. It returns labelled sample items for development/testing.").font(.caption)
            } else {
                if draft.mode == .responsesCompatible {
                    TextField("HTTPS Responses API URL", text: $draft.customEndpoint)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Must implement OpenAI's Responses image input and strict JSON-schema output format. A different API needs a service adapter.").font(.caption)
                } else { Text(FoodAnalysisConfiguration.openAIEndpoint).font(.caption).textSelection(.enabled) }
                TextField("Vision model ID", text: $draft.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Default: gpt-4.1-mini. Choose a model supporting image inputs and Structured Outputs.").font(.caption)
            }
        }
    }
    private func refreshKeyStatus() { hasSavedKey = draft.mode != .mock && settings.hasCredential(for: draft) }
}
