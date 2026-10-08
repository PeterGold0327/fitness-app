import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
#if SWIFT_PACKAGE
@testable import FitnessCore
#else
@testable import LeanLog
#endif

private actor RecordingAnalysisTransport: FoodAnalysisHTTPTransport {
    let response: AnalysisHTTPResponse
    private(set) var requests: [URLRequest] = []
    init(data: Data, status: Int = 200) { response = AnalysisHTTPResponse(data: data, status: status) }
    func send(_ request: URLRequest) async throws -> AnalysisHTTPResponse { requests.append(request); return response }
}
private struct FailingAnalysisTransport: FoodAnalysisHTTPTransport {
    let code: URLError.Code
    func send(_ request: URLRequest) async throws -> AnalysisHTTPResponse { throw URLError(code) }
}
private struct FailingFoodAnalyzer: FoodPhotoAnalyzing {
    let error: FoodAnalysisError
    func analyze(imageData: Data) async throws -> FoodEstimate { throw error }
}
private struct CancelledFoodAnalyzer: FoodPhotoAnalyzing {
    func analyze(imageData: Data) async throws -> FoodEstimate { throw CancellationError() }
}
private actor CountingDemoAnalyzer: FoodPhotoAnalyzing {
    private(set) var calls = 0
    func analyze(imageData: Data) async throws -> FoodEstimate { calls += 1; return try await MockFoodPhotoAnalyzer().analyze(imageData: imageData) }
}
final class TestFoodCredentials: FoodAnalysisCredentialStore {
    var keys: [String: String] = [:]
    var reads = 0
    func read(account: String) throws -> String? { reads += 1; return keys[account] }
    func write(_ key: String, account: String) throws { keys[account] = key }
    func delete(account: String) throws { keys.removeValue(forKey: account) }
}

final class FoodPhotoAPITests: XCTestCase {
    // JPEG signature fixture for offline request framing tests; no decoding/live API call occurs.
    private let image = Data([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0xff, 0xd9])
    private var live: FoodAnalysisConfiguration { FoodAnalysisConfiguration(mode: .openAI) }
    private func foodJSON() -> [String: Any] {
        ["name": "Chicken rice", "confidence": 0.7, "uncertainty_notes": "Portions and hidden oil are uncertain.", "items": [
            ["name": "Cooked chicken", "grams": 150, "calories": 248, "protein": 46.5, "carbs": 0, "fat": 5.4,
             "confidence": 0.8, "uncertainty_notes": "Assumed cooked breast."],
            ["name": "Cooked rice", "grams": 200, "calories": 260, "protein": 5.4, "carbs": 56, "fat": 0.6,
             "confidence": 0.6, "uncertainty_notes": "Assumed 200 g portion."]
        ]]
    }
    private func envelope(_ json: [String: Any]? = nil, status: String = "completed") throws -> Data {
        let text = String(data: try JSONSerialization.data(withJSONObject: json ?? foodJSON()), encoding: .utf8)!
        return try JSONSerialization.data(withJSONObject: ["status": status, "output": [
            ["type": "message", "content": [["type": "output_text", "text": text]]]
        ]])
    }
    private func assertParseError(_ data: Data, _ expected: FoodAnalysisError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ResponsesFoodPhotoAnalyzer.parse(data), file: file, line: line) { error in
            XCTAssertEqual(error as? FoodAnalysisError, expected, file: file, line: line)
        }
    }
    func testParsesAllItemFieldsAndComputesTotals() throws {
        let estimate = try ResponsesFoodPhotoAnalyzer.parse(envelope())
        XCTAssertEqual(estimate.source, .api)
        XCTAssertEqual(estimate.items.count, 2)
        XCTAssertEqual(estimate.items[0].grams, 150)
        XCTAssertEqual(estimate.items[0].confidence, 0.8)
        XCTAssertEqual(estimate.items[0].uncertaintyNotes, "Assumed cooked breast.")
        XCTAssertEqual(estimate.calories, 508)
        XCTAssertEqual(estimate.protein, 51.9, accuracy: 0.001)
        XCTAssertEqual(estimate.carbs, 56)
        XCTAssertEqual(estimate.fat, 6, accuracy: 0.001)
        XCTAssertEqual(estimate.confidence, 0.7)
        XCTAssertTrue(estimate.valid)
    }
    func testEditingAnItemUpdatesTotalsAndValidation() throws {
        var estimate = try ResponsesFoodPhotoAnalyzer.parse(envelope())
        estimate.items[0].grams = 100; estimate.items[0].calories = 165; estimate.items[0].protein = 31
        estimate.items[0].carbs = 1; estimate.items[0].fat = 3.6
        estimate.items[0].name = "Edited chicken"; estimate.items[0].confidence = 0.5
        estimate.items[0].uncertaintyNotes = "Weighed and reviewed."
        XCTAssertEqual(estimate.calories, 425)
        XCTAssertEqual(estimate.protein, 36.4, accuracy: 0.001)
        XCTAssertEqual(estimate.carbs, 57)
        XCTAssertEqual(estimate.fat, 4.2, accuracy: 0.001)
        XCTAssertTrue(estimate.valid)
        estimate.items[0].grams = .nan
        XCTAssertFalse(estimate.valid)
    }
    func testBuildsResponsesVisionRequestWithStrictSchemaAndNoStoredResponse() async throws {
        let transport = RecordingAnalysisTransport(data: try envelope())
        _ = try await ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "unit-test-key", transport: transport).analyze(imageData: image)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, FoodAnalysisConfiguration.openAIEndpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["model"] as? String, "gpt-4.1-mini")
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[1]["type"] as? String, "input_image")
        XCTAssertEqual(content[1]["image_url"] as? String, "data:image/jpeg;base64,\(image.base64EncodedString())")
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains("unit-test-key"))
    }
    func testMapsHTTPFailuresWithoutExposingServerBody() async throws {
        let body = Data("DO_NOT_PRINT provider error body with credential".utf8)
        for (status, expected) in [(401, FoodAnalysisError.unauthorized), (403, .unauthorized), (429, .rateLimited),
                                   (503, .server(503)), (400, .unexpectedStatus(400)), (302, .redirectRejected)] {
            let transport = RecordingAnalysisTransport(data: body, status: status)
            do {
                _ = try await ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: transport).analyze(imageData: image)
                XCTFail("Status \(status) should fail")
            } catch {
                XCTAssertEqual(error as? FoodAnalysisError, expected)
                XCTAssertFalse(error.localizedDescription.contains("DO_NOT_PRINT"))
            }
        }
    }
    func testMapsTimeoutAndOfflineErrors() async {
        for (code, expected) in [(URLError.Code.timedOut, FoodAnalysisError.timeout), (.notConnectedToInternet, .network)] {
            do {
                _ = try await ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: FailingAnalysisTransport(code: code)).analyze(imageData: image)
                XCTFail("Network error should be returned")
            } catch { XCTAssertEqual(error as? FoodAnalysisError, expected) }
        }
    }
    func testTransportCancellationIsNotAnAnalysisFailure() async {
        do {
            _ = try await ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: FailingAnalysisTransport(code: .cancelled)).analyze(imageData: image)
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testMalformedAndMissingOutputAreRejected() throws {
        assertParseError(Data("not json".utf8), .invalidResponse)
        assertParseError(try JSONSerialization.data(withJSONObject: ["status": "completed", "output": []]), .invalidResponse)
        assertParseError(try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": "```json\n{}\n```"]]]]]), .invalidResponse)
        let oversized = Data(repeating: 0, count: 2 * 1024 * 1024 + 1)
        assertParseError(oversized, .invalidResponse)
    }
    func testRefusedAndIncompleteResponsesAreNotFood() throws {
        assertParseError(try envelope(status: "incomplete"), .incomplete)
        let refused: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "refusal", "refusal": "No"]]]]]
        assertParseError(try JSONSerialization.data(withJSONObject: refused), .refused)
    }
    func testNoFoodIsReportedInsteadOfInventedMeal() throws {
        var json = foodJSON(); json["items"] = []
        assertParseError(try envelope(json), .noFoodDetected)
    }
    func testMissingNumericFieldsNegativeValuesAndUnusableConfidenceAreRejected() throws {
        for (field, value) in [("grams", -1.0), ("calories", -1), ("protein", 4000), ("confidence", 1.1)] {
            var json = foodJSON(); var items = json["items"] as! [[String: Any]]
            items[0][field] = value; json["items"] = items
            assertParseError(try envelope(json), .invalidResponse)
        }
        var json = foodJSON(); var items = json["items"] as! [[String: Any]]
        items[0].removeValue(forKey: "carbs"); json["items"] = items
        assertParseError(try envelope(json), .invalidResponse)
    }
    func testTooManyItemsAndAbsurdCombinedTotalsAreRejected() throws {
        var json = foodJSON(); let item = (json["items"] as! [[String: Any]])[0]
        json["items"] = Array(repeating: item, count: 31)
        assertParseError(try envelope(json), .invalidResponse)
        var huge = item; huge["calories"] = 15000
        json["items"] = [huge, huge]
        assertParseError(try envelope(json), .invalidResponse)
    }
    func testBadPhotoAndMissingKeyDoNotMakeNetworkRequests() async throws {
        let transport = RecordingAnalysisTransport(data: try envelope())
        for (data, key, expected) in [(Data(), "key", FoodAnalysisError.invalidImage),
                                      (Data([1, 2, 3, 4]), "key", .invalidImage),
                                      (image, "", .missingCredential),
                                      (image, "key\nheader", .missingCredential),
                                      (Data(repeating: 0, count: 6 * 1024 * 1024 + 1), "key", .imageTooLarge)] {
            do {
                _ = try await ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: key, transport: transport).analyze(imageData: data)
                XCTFail("Invalid input should not upload")
            } catch { XCTAssertEqual(error as? FoodAnalysisError, expected) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
    func testConfigurationRejectsInsecureAndCredentialBearingURLs() {
        for endpoint in ["http://example.com/responses", "https://user:secret@example.com/responses", "https://example.com/responses?key=secret",
                         "https://example.com/responses#fragment", "https://example.com:444/responses", "not-a-url"] {
            var configuration = FoodAnalysisConfiguration(mode: .responsesCompatible)
            configuration.customEndpoint = endpoint
            XCTAssertFalse(configuration.valid)
            XCTAssertNil(configuration.credentialAccount)
        }
        var configuration = live; configuration.model = "  "
        XCTAssertFalse(configuration.valid)
    }
    func testConfigurationSerializationNeverContainsCredential() throws {
        let configuration = FoodAnalysisConfiguration(mode: .openAI)
        let json = String(data: try JSONEncoder().encode(configuration), encoding: .utf8)!
        XCTAssertFalse(json.lowercased().contains("key"))
        XCTAssertFalse(configuration.allowDemoFallback)
        XCTAssertEqual(FoodAnalysisConfiguration().mode, .mock)
    }
    func testEndpointChangeDoesNotReuseExistingCredential() async throws {
        let credentials = TestFoodCredentials()
        let old = live; credentials.keys[old.credentialAccount!] = "test-original-key"
        var changed = FoodAnalysisConfiguration(mode: .responsesCompatible)
        changed.customEndpoint = "https://different.example/v1/responses"
        let transport = RecordingAnalysisTransport(data: try envelope())
        let analyzer = try FoodAnalysisServiceFactory.make(configuration: changed, credentials: credentials, transport: transport)
        do { _ = try await analyzer.analyze(imageData: image); XCTFail("New endpoint needs its own credential") }
        catch { XCTAssertEqual(error as? FoodAnalysisError, .missingCredential) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
    func testMockModeDoesNotReadKeyOrUploadImage() async throws {
        let credentials = TestFoodCredentials()
        let transport = RecordingAnalysisTransport(data: try envelope())
        let analyzer = try FoodAnalysisServiceFactory.make(configuration: FoodAnalysisConfiguration(), credentials: credentials, transport: transport)
        let result = try await analyzer.analyze(imageData: image)
        XCTAssertEqual(result.source, .mock)
        XCTAssertEqual(credentials.reads, 0)
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
    func testFallbackOnlyRunsWhenExplicitlyEnabledAndIsLabelled() async throws {
        let demo = CountingDemoAnalyzer()
        let off = FallbackFoodPhotoAnalyzer(primary: FailingFoodAnalyzer(error: .rateLimited), fallback: demo, enabled: false)
        do { _ = try await off.analyze(imageData: image); XCTFail("Disabled fallback must fail") }
        catch { XCTAssertEqual(error as? FoodAnalysisError, .rateLimited) }
        let callsBefore = await demo.calls; XCTAssertEqual(callsBefore, 0)
        let on = FallbackFoodPhotoAnalyzer(primary: FailingFoodAnalyzer(error: .network), fallback: demo, enabled: true)
        let result = try await on.analyze(imageData: image)
        XCTAssertEqual(result.source, .mockFallback)
        XCTAssertTrue(result.explanation.contains(FoodAnalysisError.network.localizedDescription))
        XCTAssertEqual(result.confidence, 0)
        let callsAfter = await demo.calls; XCTAssertEqual(callsAfter, 1)
    }
    func testCancellationAndInvalidInputNeverTriggerFallback() async {
        let demo = CountingDemoAnalyzer()
        let cancelled = FallbackFoodPhotoAnalyzer(primary: CancelledFoodAnalyzer(), fallback: demo, enabled: true)
        do { _ = try await cancelled.analyze(imageData: image); XCTFail("Cancellation expected") }
        catch { XCTAssertTrue(error is CancellationError) }
        for expected in [FoodAnalysisError.invalidImage, .imageTooLarge, .invalidConfiguration] {
            let analyzer = FallbackFoodPhotoAnalyzer(primary: FailingFoodAnalyzer(error: expected), fallback: demo, enabled: true)
            do { _ = try await analyzer.analyze(imageData: image); XCTFail("Input error expected") }
            catch { XCTAssertEqual(error as? FoodAnalysisError, expected) }
        }
        let calls = await demo.calls; XCTAssertEqual(calls, 0)
    }
    func testSuccessfulPrimaryNeverUsesFallback() async throws {
        let demo = CountingDemoAnalyzer()
        let transport = RecordingAnalysisTransport(data: try envelope())
        let primary = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: transport)
        let result = try await FallbackFoodPhotoAnalyzer(primary: primary, fallback: demo, enabled: true).analyze(imageData: image)
        XCTAssertEqual(result.source, .api)
        let calls = await demo.calls; XCTAssertEqual(calls, 0)
    }
    func testMissingCredentialCanUseExplicitDevelopmentFallback() async throws {
        let credentials = TestFoodCredentials(); var configuration = live; configuration.allowDemoFallback = true
        let analyzer = try FoodAnalysisServiceFactory.make(configuration: configuration, credentials: credentials)
        let estimate = try await analyzer.analyze(imageData: image)
        XCTAssertEqual(estimate.source, .mockFallback)
        XCTAssertTrue(estimate.explanation.contains(FoodAnalysisError.missingCredential.localizedDescription))
    }
}
