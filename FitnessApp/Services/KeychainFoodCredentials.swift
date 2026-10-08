import Foundation
import Security

/// Personal user-provided API keys. Never stored in SwiftData/UserDefaults/source files.
struct KeychainFoodCredentials: FoodAnalysisCredentialStore {
    private let service = "LeanLog.FoodPhotoAnalysis"
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
    func read(account: String) throws -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw CredentialError.unavailable
        }
        return key
    }
    func write(_ key: String, account: String) throws {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.utf8.count <= 4096,
              cleaned.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw CredentialError.invalidKey }
        let values: [String: Any] = [kSecValueData as String: Data(cleaned.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(account) as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var new = query(account)
            for (key, value) in values { new[key] = value }
            guard SecItemAdd(new as CFDictionary, nil) == errSecSuccess else { throw CredentialError.unavailable }
        } else if status != errSecSuccess { throw CredentialError.unavailable }
    }
    func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.unavailable }
    }
    enum CredentialError: Error, LocalizedError {
        case unavailable, invalidKey
        var errorDescription: String? {
            switch self {
            case .unavailable: return L10n.text("The iPhone Keychain could not be accessed. Unlock the device and retry.")
            case .invalidKey: return L10n.text("Enter a valid API key without spaces or control characters.")
            }
        }
    }
}
