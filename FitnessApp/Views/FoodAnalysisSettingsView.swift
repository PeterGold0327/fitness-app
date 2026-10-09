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
                uploadSection
            }
            if let message = settings.message { Section { Text(message).foregroundStyle(.red) } }
            if !draft.valid { Section { Text(L10n.text("Use a valid HTTPS API URL without user info, query, fragment or a nonstandard port, and a nonempty model ID.")).foregroundStyle(.red) } }
        }.navigationTitle(L10n.text("Food photo analysis")).keyboardDoneButton()
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(L10n.text("Save")) { if settings.save(draft, newKey: newKey) { newKey = ""; dismiss() } }.disabled(!draft.valid)
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
        Section(L10n.text("Photo upload")) {
            Text(L10n.text("Tapping Analyze uploads that photo to %@. Nothing uploads when you select/capture a photo. Calls may incur your provider's API charges.", String(describing: draft.endpointURL?.host ?? L10n.text("the configured provider"))))
            Text(L10n.text("OpenAI requests set store=false. Provider processing and retention policies still apply. No photo/request/key is written to debug logs.")).font(.caption)
        }
    }

    private var credentialSection: some View {
        Section(L10n.text("API credential")) {
            Text(hasSavedKey ? L10n.text("A key is stored for this exact endpoint.") : L10n.text("No key is stored for this endpoint."))
            SecureField(hasSavedKey ? L10n.text("Replacement API key (optional)") : L10n.text("API key"), text: $newKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            Text(L10n.text("Keys are saved in this iPhone's Keychain, not source files or the nutrition database. Leaving the field empty keeps the stored key. A changed endpoint needs its own key.")).font(.caption)
            if hasSavedKey {
                Button(L10n.text("Remove stored key"), role: .destructive) {
                    if settings.removeKey(for: draft) { newKey = ""; refreshKeyStatus() }
                }
            }
        }
    }

    private var providerSection: some View {
        Section(L10n.text("Analysis provider")) {
            Picker(L10n.text("Provider"), selection: $draft.mode) {
                ForEach(FoodAnalysisMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if draft.mode == .mock {
                Text(L10n.text("Demo mode never uploads a photo. It returns labelled sample items for development/testing.")).font(.caption)
            } else {
                DisclosureGroup(L10n.text("Advanced provider settings")) {
                    if draft.mode == .responsesCompatible {
                        TextField(L10n.text("HTTPS Responses API URL"), text: $draft.customEndpoint)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text(L10n.text("Must implement OpenAI's Responses image input and strict JSON-schema output format. A different API needs a service adapter.")).font(.caption)
                    } else { Text(FoodAnalysisConfiguration.openAIEndpoint).font(.caption).textSelection(.enabled) }
                    TextField(L10n.text("Vision model ID"), text: $draft.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(L10n.text("Default: gpt-4.1-mini. Choose a model supporting image inputs and Structured Outputs.")).font(.caption)
                    Toggle(L10n.text("Allow labelled demo fallback"), isOn: $draft.allowDemoFallback)
                    Text(draft.allowDemoFallback
                        ? L10n.text("Development/testing only. A failed API call may show fixed demo items, clearly labelled as fallback. Verify or replace every value.")
                        : L10n.text("Your existing draft stays intact. Retry, switch to demo mode, or enter the meal manually. No automatic fake result.")).font(.caption)
                }
            }
        }
    }
    private func refreshKeyStatus() { hasSavedKey = draft.mode != .mock && settings.hasCredential(for: draft) }
}
