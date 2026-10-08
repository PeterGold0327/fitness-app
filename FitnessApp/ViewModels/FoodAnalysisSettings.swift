import Foundation
import Combine

@MainActor final class FoodAnalysisSettings: ObservableObject {
    @Published private(set) var configuration: FoodAnalysisConfiguration
    @Published var message: String?
    private let credentials: any FoodAnalysisCredentialStore
    private let defaults: UserDefaults
    private let preferenceKey = "foodAnalysisConfiguration"
    init(credentials: any FoodAnalysisCredentialStore = KeychainFoodCredentials(), defaults: UserDefaults = .standard) {
        self.credentials = credentials; self.defaults = defaults
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") { configuration = FoodAnalysisConfiguration(); return }
        #endif
        if let data = defaults.data(forKey: preferenceKey),
           let decoded = try? JSONDecoder().decode(FoodAnalysisConfiguration.self, from: data), decoded.valid {
            configuration = decoded
        } else { configuration = FoodAnalysisConfiguration() }
    }
    func hasCredential(for draft: FoodAnalysisConfiguration) -> Bool {
        guard let account = draft.credentialAccount else { return false }
        do { return try credentials.read(account: account)?.isEmpty == false }
        catch { message = error.localizedDescription; return false }
    }
    @discardableResult func save(_ draft: FoodAnalysisConfiguration, newKey: String) -> Bool {
        var draft = draft
        draft.model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.customEndpoint = draft.customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.valid else { message = FoodAnalysisError.invalidConfiguration.localizedDescription; return false }
        do {
            let data = try JSONEncoder().encode(draft)
            if draft.mode != .mock, !newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let account = draft.credentialAccount else { throw FoodAnalysisError.invalidConfiguration }
                try credentials.write(newKey, account: account)
            }
            defaults.set(data, forKey: preferenceKey)
            configuration = draft
            message = nil
            return true
        } catch { message = error.localizedDescription; return false }
    }
    @discardableResult func removeKey(for draft: FoodAnalysisConfiguration) -> Bool {
        guard let account = draft.credentialAccount else { return false }
        do { try credentials.delete(account: account); message = nil; objectWillChange.send(); return true }
        catch { message = error.localizedDescription; return false }
    }
    func analyzer() throws -> any FoodPhotoAnalyzing {
        try FoodAnalysisServiceFactory.make(configuration: configuration, credentials: credentials)
    }
}
