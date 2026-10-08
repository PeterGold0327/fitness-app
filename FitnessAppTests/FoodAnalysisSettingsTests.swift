#if !SWIFT_PACKAGE
import XCTest
@testable import LeanLog

private final class SettingsTestCredentials: FoodAnalysisCredentialStore {
    var values: [String: String] = [:]
    var failWrite = false
    func read(account: String) throws -> String? { values[account] }
    func write(_ key: String, account: String) throws {
        if failWrite { throw FoodAnalysisError.missingCredential }
        values[account] = key
    }
    func delete(account: String) throws { values.removeValue(forKey: account) }
}

@MainActor final class FoodAnalysisSettingsTests: XCTestCase {
    private func preferences() -> (UserDefaults, String) {
        let name = "LeanLog.AnalysisTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }
    func testSettingsPersistWithoutKeyAndBlankKeyPreservesCredential() throws {
        let (defaults, domain) = preferences(); defer { defaults.removePersistentDomain(forName: domain) }
        let keys = SettingsTestCredentials()
        let settings = FoodAnalysisSettings(credentials: keys, defaults: defaults)
        var config = FoodAnalysisConfiguration(); config.mode = .openAI; config.model = " gpt-4.1-mini "
        XCTAssertTrue(settings.save(config, newKey: "unit-test-secret"))
        let data = try XCTUnwrap(defaults.data(forKey: "foodAnalysisConfiguration"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("unit-test-secret"))
        let reopened = FoodAnalysisSettings(credentials: keys, defaults: defaults)
        XCTAssertEqual(reopened.configuration.model, "gpt-4.1-mini")
        XCTAssertTrue(reopened.hasCredential(for: config))
        config.allowDemoFallback = true
        XCTAssertTrue(reopened.save(config, newKey: ""))
        XCTAssertEqual(keys.values[config.credentialAccount!], "unit-test-secret")
        XCTAssertTrue(reopened.removeKey(for: config))
        XCTAssertFalse(reopened.hasCredential(for: config))
    }
    func testCredentialFailureDoesNotCommitConfiguration() {
        let (defaults, domain) = preferences(); defer { defaults.removePersistentDomain(forName: domain) }
        let keys = SettingsTestCredentials(); keys.failWrite = true
        let settings = FoodAnalysisSettings(credentials: keys, defaults: defaults)
        var config = FoodAnalysisConfiguration(); config.mode = .openAI
        XCTAssertFalse(settings.save(config, newKey: "test-key"))
        XCTAssertEqual(settings.configuration.mode, .mock)
        XCTAssertNil(defaults.data(forKey: "foodAnalysisConfiguration"))
        XCTAssertNotNil(settings.message)
    }
}
#endif
