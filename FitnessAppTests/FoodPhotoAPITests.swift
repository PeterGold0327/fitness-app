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
private actor SequencedMealTransport: FoodAnalysisHTTPTransport {
    var responses: [AnalysisHTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ data: [Data]) { responses = data.map { AnalysisHTTPResponse(data: $0, status: 200) } }
    func send(_ request: URLRequest) async throws -> AnalysisHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw FoodAnalysisError.network }
        return responses.removeFirst()
    }
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
    private func detectionJSON() -> [String: Any] {
        ["name": "中式午餐", "confidence": 0.65, "uncertainty_notes": "油量未知，熟重估算", "items": [
            ["name": "宫保鸡丁", "grams": 180, "confidence": 0.6, "uncertainty_notes": "花生和油量不确定"],
            ["name": "米饭", "grams": 200, "confidence": 0.9, "uncertainty_notes": "熟重"],
            ["name": "疑似汤", "grams": 100, "confidence": 0.2, "uncertainty_notes": "可能没有喝汤"]
        ]]
    }
    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
    private func requestPrompt(_ request: URLRequest) throws -> String {
        let input = try XCTUnwrap(try requestBody(request)["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        return try XCTUnwrap(content[0]["text"] as? String)
    }
    func testTwoStepChineseMealReviewAddRemoveCorrectAndRecalculate() async throws {
        var nutrition = detectionJSON()
        nutrition["items"] = [
            ["name": "番茄炒蛋", "grams": 180, "calories": 240, "protein": 14, "carbs": 10, "fat": 16,
             "confidence": 0.7, "uncertainty_notes": "少油"],
            ["name": "米饭", "grams": 150, "calories": 195, "protein": 4, "carbs": 42, "fat": 0.5,
             "confidence": 0.9, "uncertainty_notes": "用户称重"],
            ["name": "青菜", "grams": 100, "calories": 60, "protein": 2, "carbs": 5, "fat": 4,
             "confidence": 0.5, "uncertainty_notes": "少油"]
        ]
        let transport = SequencedMealTransport([try envelope(detectionJSON()), try envelope(nutrition)])
        let analyzer = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: transport)
        var reviewed = try await analyzer.detect(imageData: image, context: "家常菜，少油")
        XCTAssertEqual(reviewed.items.count, 3)
        XCTAssertEqual(reviewed.calories, 0, "Detection does not produce nutrition")
        let beforeReview = await transport.requests
        XCTAssertEqual(beforeReview.count, 1, "Nutrition requires a separate user action")
        reviewed.items[0].name = "番茄炒蛋"
        reviewed.items[1].grams = 150
        reviewed.items.removeLast()
        reviewed.items.append(EstimatedFoodItem(name: "青菜", grams: 100, calories: 0, protein: 0,
            carbs: 0, fat: 0, confidence: 0.5, uncertaintyNotes: "用户添加"))
        let result = try await analyzer.estimateNutrition(imageData: image, reviewed: reviewed, context: "不是宫保鸡丁，是番茄炒蛋；米饭熟重150克；不喝汤")
        XCTAssertEqual(result.items.map(\.name), ["番茄炒蛋", "米饭", "青菜"])
        XCTAssertEqual(result.items.map(\.id), reviewed.items.map(\.id))
        XCTAssertEqual(result.name, reviewed.name)
        XCTAssertEqual(result.calories, 495)
        XCTAssertEqual(result.protein, 20)
        XCTAssertEqual(result.carbs, 57)
        XCTAssertEqual(result.fat, 20.5)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let prompt = try requestPrompt(requests[1])
        XCTAssertTrue(prompt.contains("米饭熟重150克"))
        XCTAssertTrue(prompt.contains("番茄炒蛋"))
        XCTAssertFalse(prompt.contains("疑似汤"), "Removed foods must not be in the reviewed list")
        XCTAssertFalse(prompt.contains("\"calories\":"), "Provisional nutrition must not anchor the new estimate")
        for request in requests { XCTAssertEqual(try requestBody(request)["store"] as? Bool, false) }
    }
    func testDetectionSchemaExcludesNutritionAndIncludesChineseMixedMealGuidance() async throws {
        let transport = RecordingAnalysisTransport(data: try envelope(detectionJSON()))
        let analyzer = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: transport)
        _ = try await analyzer.detect(imageData: image, context: "麻辣烫不喝汤")
        let requests = await transport.requests
        let body = try requestBody(requests[0])
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let items = try XCTUnwrap(properties["items"] as? [String: Any])
        let item = try XCTUnwrap(items["items"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(item["required"] as? [String])), Set(["name", "grams", "confidence", "uncertainty_notes"]))
        let prompt = try requestPrompt(requests[0])
        for dish in ["盖浇饭", "麻辣烫", "火锅", "炒饭", "饺子", "麻婆豆腐", "红烧肉"] { XCTAssertTrue(prompt.contains(dish)) }
        XCTAssertTrue(prompt.contains("麻辣烫不喝汤"))
    }
    func testReanalysisUsesNewContextWithoutMutatingPriorReview() async throws {
        var corrected = detectionJSON()
        corrected["items"] = [["name": "麻婆豆腐", "grams": 220, "confidence": 0.8, "uncertainty_notes": "用户说明"]]
        let transport = SequencedMealTransport([try envelope(detectionJSON()), try envelope(corrected)])
        let analyzer = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: transport)
        let original = try await analyzer.detect(imageData: image, context: "")
        let revised = try await analyzer.detect(imageData: image, context: "这是麻婆豆腐，不是鸡肉")
        XCTAssertEqual(original.items[0].name, "宫保鸡丁")
        XCTAssertEqual(revised.items[0].name, "麻婆豆腐")
        let requests = await transport.requests
        XCTAssertTrue(try requestPrompt(requests[1]).contains("这是麻婆豆腐，不是鸡肉"))
    }
    func testNutritionRejectsChangedNamesPortionsAddedRemovedOrReorderedFoods() throws {
        let reviewed = try ResponsesFoodPhotoAnalyzer.parse(envelope())
        var candidates: [FoodEstimate] = []
        var changed = reviewed; changed.items[0].name = "Wrong dish"; candidates.append(changed)
        changed = reviewed; changed.items[0].grams += 10; candidates.append(changed)
        changed = reviewed; changed.items.reverse(); candidates.append(changed)
        changed = reviewed; changed.items.removeLast(); candidates.append(changed)
        changed = reviewed; changed.items.append(reviewed.items[0]); candidates.append(changed)
        for result in candidates {
            XCTAssertThrowsError(try FoodReview.merge(result, reviewed: reviewed)) {
                XCTAssertEqual($0 as? FoodAnalysisError, .invalidResponse)
            }
        }
    }
    func testCorrectingPortionRescalesNutritionAndRemovingFoodUpdatesTotals() throws {
        var meal = try ResponsesFoodPhotoAnalyzer.parse(envelope())
        let originalID = meal.items[0].id
        meal.items[0].resize(to: 75)
        XCTAssertEqual(meal.items[0].id, originalID)
        XCTAssertEqual(meal.items[0].calories, 124)
        XCTAssertEqual(meal.items[0].protein, 23.25)
        XCTAssertEqual(meal.items[0].fat, 2.7)
        XCTAssertEqual(meal.calories, 384)
        // Preserve a manual nutrition correction as the new per-gram baseline.
        meal.items[0].calories = 150
        meal.items[0].resize(to: 150)
        XCTAssertEqual(meal.items[0].calories, 300)
        meal.items.removeLast()
        XCTAssertEqual(meal.calories, 300)
        XCTAssertEqual(meal.protein, 46.5)
        XCTAssertTrue(meal.valid)
    }
    func testConfidenceLabelsHaveExplicitBoundaries() throws {
        var item = try ResponsesFoodPhotoAnalyzer.parse(envelope()).items[0]
        for (confidence, label) in [(0.0, "Low confidence"), (0.49, "Low confidence"),
                                    (0.5, "Medium confidence"), (0.79, "Medium confidence"),
                                    (0.8, "High confidence"), (1.0, "High confidence")] {
            item.confidence = confidence
            XCTAssertEqual(item.confidenceLevel, L10n.text(label))
        }
    }
    func testInvalidDetectionAndEmptyFoodsAreRejected() throws {
        for value in [-0.1, 1.1] {
            var json = detectionJSON(); json["confidence"] = value
            XCTAssertThrowsError(try ResponsesFoodPhotoAnalyzer.parse(envelope(json), detection: true))
        }
        var empty = detectionJSON(); empty["items"] = []
        XCTAssertThrowsError(try ResponsesFoodPhotoAnalyzer.parse(envelope(empty), detection: true)) {
            XCTAssertEqual($0 as? FoodAnalysisError, .noFoodDetected)
        }
        var invalid = detectionJSON()
        invalid["items"] = [["name": "米饭", "grams": -1, "confidence": 0.9, "uncertainty_notes": ""]]
        XCTAssertThrowsError(try ResponsesFoodPhotoAnalyzer.parse(envelope(invalid), detection: true))
    }
    func testOversizedContextAndInvalidReviewDoNotUploadOrFallback() async throws {
        let transport = RecordingAnalysisTransport(data: try envelope())
        let primary = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: transport)
        let fallback = CountingDemoAnalyzer()
        let analyzer = FallbackFoodPhotoAnalyzer(primary: primary, fallback: fallback, enabled: true)
        let reviewed = try ResponsesFoodPhotoAnalyzer.parse(envelope())
        do {
            _ = try await analyzer.detect(imageData: image, context: String(repeating: "饭", count: 2001))
            XCTFail("Oversized context should fail")
        } catch { XCTAssertEqual(error as? FoodAnalysisError, .invalidContext) }
        var empty = reviewed; empty.items = []
        do {
            _ = try await analyzer.estimateNutrition(imageData: image, reviewed: empty, context: "")
            XCTFail("Empty review should fail")
        } catch { XCTAssertEqual(error as? FoodAnalysisError, .invalidResponse) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
        let calls = await fallback.calls; XCTAssertEqual(calls, 0)
    }
    func testFailedNutritionLeavesReviewUsableAndCancellationDoesNotFallback() async throws {
        let reviewed = try ResponsesFoodPhotoAnalyzer.parse(envelope())
        let transport = RecordingAnalysisTransport(data: Data(), status: 429)
        let primary = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: transport)
        do {
            _ = try await primary.estimateNutrition(imageData: image, reviewed: reviewed, context: "少油")
            XCTFail("Rate limiting must be reported")
        } catch { XCTAssertEqual(error as? FoodAnalysisError, .rateLimited) }
        XCTAssertEqual(reviewed.calories, 508)
        let cancelled = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: FailingAnalysisTransport(code: .cancelled))
        let fallback = CountingDemoAnalyzer()
        let analyzer = FallbackFoodPhotoAnalyzer(primary: cancelled, fallback: fallback, enabled: true)
        do {
            _ = try await analyzer.estimateNutrition(imageData: image, reviewed: reviewed, context: "")
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
        let calls = await fallback.calls; XCTAssertEqual(calls, 0)
    }
    func testDemoNutritionPreservesCorrectedFoodsWithoutInventingNameBasedMacros() async throws {
        var reviewed = try ResponsesFoodPhotoAnalyzer.parse(envelope())
        reviewed.items.removeFirst()
        reviewed.items[0].name = "手动更正的炒饭"
        reviewed.items[0].calories = 400
        let result = try await MockFoodPhotoAnalyzer().estimateNutrition(imageData: image, reviewed: reviewed, context: "少油")
        XCTAssertEqual(result.items.map(\.name), ["手动更正的炒饭"])
        XCTAssertEqual(result.calories, 400)
        XCTAssertEqual(result.items[0].id, reviewed.items[0].id)
        XCTAssertEqual(result.source, .mock)
        XCTAssertEqual(result.confidence, 0)
        XCTAssertEqual(result.items[0].confidence, 0)
    }
    func testContextualFactoryDispatchesDetectionAndNutritionThroughFallbackWrapper() async throws {
        let credentials = TestFoodCredentials(); credentials.keys[live.credentialAccount!] = "test-key"
        let detection = try envelope(detectionJSON())
        var nutrition = detectionJSON()
        var items = nutrition["items"] as! [[String: Any]]
        for index in items.indices {
            items[index]["calories"] = 100
            items[index]["protein"] = 5
            items[index]["carbs"] = 10
            items[index]["fat"] = 4
        }
        nutrition["items"] = items
        let transport = SequencedMealTransport([detection, try envelope(nutrition)])
        let analyzer = try FoodAnalysisServiceFactory.make(configuration: live, credentials: credentials, transport: transport)
        let result = try await analyzer.detect(imageData: image, context: "少油")
        XCTAssertEqual(result.calories, 0)
        XCTAssertEqual(result.items[0].name, "宫保鸡丁")
        let estimated = try await analyzer.estimateNutrition(imageData: image, reviewed: result, context: "少油")
        XCTAssertEqual(estimated.calories, 300)
        XCTAssertEqual(estimated.items.map(\.id), result.items.map(\.id))
        let fallbackTransport = RecordingAnalysisTransport(data: Data(), status: 503)
        let failing = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: fallbackTransport)
        let withFallback = FallbackFoodPhotoAnalyzer(primary: failing, fallback: MockFoodPhotoAnalyzer(), enabled: true)
        let fallbackResult = try await withFallback.estimateNutrition(imageData: image, reviewed: estimated, context: "少油")
        XCTAssertEqual(fallbackResult.source, .mockFallback)
        XCTAssertEqual(fallbackResult.items.map(\.name), estimated.items.map(\.name))
        XCTAssertEqual(fallbackResult.calories, 300)
        XCTAssertEqual(fallbackResult.confidence, 0)
    }

    private func simpleComponents() -> [String: Any] {
        ["name": "中式午餐", "items": [
            ["name": "米饭", "grams": 282.7, "calories": 364.2, "protein": 7.2, "carbs": 79.6, "fat": 0.8],
            ["name": "西兰花", "grams": 119.2, "calories": 41.7, "protein": 3.4, "carbs": 8.1, "fat": 0.5],
            ["name": "鸡肉", "grams": 158.3, "calories": 262.2, "protein": 49.3, "carbs": 0, "fat": 5.7]
        ]]
    }
    func testOnePhotoRequestReturnsRoundedComponentsAndReadyToSaveNutrition() async throws {
        let transport = RecordingAnalysisTransport(data: try envelope(simpleComponents()))
        let analyzer = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: transport)
        let result = try await analyzer.analyze(imageData: image, context: "米饭、西兰花和鸡肉，少油")
        XCTAssertEqual(result.items.map(\.name), ["米饭", "西兰花", "鸡肉"])
        XCTAssertEqual(result.items.map(\.grams), [280, 120, 160])
        XCTAssertEqual(result.items.map(\.calories), [365, 40, 260])
        XCTAssertEqual(result.calories, 665)
        XCTAssertEqual(result.protein, 59)
        XCTAssertEqual(result.carbs, 88)
        XCTAssertEqual(result.fat, 8)
        XCTAssertTrue(result.valid, "Nutrition is usable immediately without a review/second request")
        XCTAssertTrue(result.uncertaintyNotes.isEmpty)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(try requestPrompt(requests[0]).contains("米饭、西兰花和鸡肉，少油"))
    }
    func testSimpleRequestUsesOnlyComponentNutritionSchemaAndNoRequiredContext() async throws {
        let transport = RecordingAnalysisTransport(data: try envelope(simpleComponents()))
        let analyzer = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: transport)
        _ = try await analyzer.analyze(imageData: image)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let body = try requestBody(requests[0])
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), Set(["name", "items"]))
        let item = try XCTUnwrap((properties["items"] as? [String: Any])?["items"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(item["required"] as? [String])), Set(["name", "grams", "calories", "protein", "carbs", "fat"]))
        let fields = try XCTUnwrap(item["properties"] as? [String: [String: Any]])
        for field in ["grams", "calories", "protein", "carbs", "fat"] { XCTAssertEqual(fields[field]?["type"] as? String, "number") }
        let prompt = try requestPrompt(requests[0])
        for food in ["米饭", "西兰花", "白菜", "番茄", "土豆", "鸡肉", "猪肉", "牛肉", "鸡蛋", "豆腐", "面条"] { XCTAssertTrue(prompt.contains(food), food) }
        XCTAssertTrue(prompt.contains("without follow-up questions"))
    }
    func testSimpleResultCorrectionsAdditionsAndRemovalsImmediatelyRecomputeAllTotals() throws {
        var result = try ResponsesFoodPhotoAnalyzer.parse(envelope(simpleComponents()), simple: true).practicalEstimate
        result.items[0].resize(to: 140)
        result.items[1].name = "白菜"
        result.items[1].calories = 35
        result.items[1].protein = 2
        result.items[1].carbs = 7
        result.items[1].fat = 0
        result.items.removeLast()
        result.items.append(EstimatedFoodItem(name: "豆腐", grams: 100, calories: 80, protein: 8, carbs: 2, fat: 4, confidence: 0, uncertaintyNotes: ""))
        XCTAssertEqual(result.calories, 297.5)
        XCTAssertEqual(result.protein, 13.5)
        XCTAssertEqual(result.carbs, 49)
        XCTAssertEqual(result.fat, 4.5)
        XCTAssertTrue(result.valid)
        // Rounding is only applied to generated responses; manual changes retain their values.
        XCTAssertEqual(result.items[0].calories, 182.5)
        result.items.removeAll()
        XCTAssertEqual(result.calories, 0)
        XCTAssertEqual(result.protein, 0)
        XCTAssertEqual(result.carbs, 0)
        XCTAssertEqual(result.fat, 0)
    }
    func testSimpleContextReanalysisThroughFactoryAndFailurePreservesPreviousEstimate() async throws {
        let credentials = TestFoodCredentials(); credentials.keys[live.credentialAccount!] = "test-key"
        var revised = simpleComponents()
        revised["items"] = [["name": "豆腐", "grams": 220, "calories": 175, "protein": 18, "carbs": 4, "fat": 9]]
        let transport = SequencedMealTransport([try envelope(simpleComponents()), try envelope(revised)])
        let analyzer = try FoodAnalysisServiceFactory.make(configuration: live, credentials: credentials, transport: transport)
        let original = try await analyzer.analyze(imageData: image, context: "")
        let corrected = try await analyzer.analyze(imageData: image, context: "这是豆腐，不是鸡肉")
        XCTAssertEqual(original.items[2].name, "鸡肉")
        XCTAssertEqual(corrected.items.map(\.name), ["豆腐"])
        XCTAssertEqual(corrected.calories, 175)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(try requestPrompt(requests[1]).contains("这是豆腐，不是鸡肉"))
        do { _ = try await analyzer.analyze(imageData: image, context: "再试一次"); XCTFail("Transport is exhausted") }
        catch { XCTAssertEqual(error as? FoodAnalysisError, .network) }
        XCTAssertEqual(corrected.calories, 175)
        XCTAssertTrue(corrected.valid)
    }
    func testSimpleInvalidContextCancellationAndLabelledFallback() async throws {
        let transport = RecordingAnalysisTransport(data: Data(), status: 503)
        let primary = ResponsesFoodPhotoAnalyzer(configuration: live, apiKey: "test-key", transport: transport)
        let demo = CountingDemoAnalyzer()
        let analyzer = FallbackFoodPhotoAnalyzer(primary: primary, fallback: demo, enabled: true)
        do { _ = try await analyzer.analyze(imageData: image, context: String(repeating: "饭", count: 2001)); XCTFail("Context limit") }
        catch { XCTAssertEqual(error as? FoodAnalysisError, .invalidContext) }
        let before = await transport.requests; XCTAssertTrue(before.isEmpty)
        let result = try await analyzer.analyze(imageData: image, context: "米饭")
        XCTAssertEqual(result.source, .mockFallback)
        XCTAssertTrue(result.valid)
        XCTAssertTrue(result.uncertaintyNotes.contains(FoodAnalysisError.server(503).localizedDescription))
        let cancelled = FallbackFoodPhotoAnalyzer(primary: CancelledFoodAnalyzer(), fallback: demo, enabled: true)
        do { _ = try await cancelled.analyze(imageData: image, context: ""); XCTFail("Cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let calls = await demo.calls; XCTAssertEqual(calls, 1)
    }
    func testSimpleNoFoodMissingMacrosAndInvalidPortionsAreRejected() throws {
        var empty = simpleComponents(); empty["items"] = []
        XCTAssertThrowsError(try ResponsesFoodPhotoAnalyzer.parse(envelope(empty), simple: true)) {
            XCTAssertEqual($0 as? FoodAnalysisError, .noFoodDetected)
        }
        for field in ["grams", "calories", "protein", "carbs", "fat"] {
            var json = simpleComponents(); var items = json["items"] as! [[String: Any]]
            items[0].removeValue(forKey: field); json["items"] = items
            XCTAssertThrowsError(try ResponsesFoodPhotoAnalyzer.parse(envelope(json), simple: true))
        }
        for value in [-1.0, 0, 10001] {
            var json = simpleComponents(); var items = json["items"] as! [[String: Any]]
            items[0]["grams"] = value; json["items"] = items
            XCTAssertThrowsError(try ResponsesFoodPhotoAnalyzer.parse(envelope(json), simple: true))
        }
    }

    func testReanalysisRetainsManualNamesPortionsNutritionAndMissingFoodCorrections() throws {
        let original = try ResponsesFoodPhotoAnalyzer.parse(envelope())
        var edited = original
        edited.items[0].name = "豆腐"
        edited.items[0].resize(to: 123)
        edited.items[0].protein = 11.5
        edited.items.removeLast()
        edited.items.append(EstimatedFoodItem(name: "白菜", grams: 100, calories: 35, protein: 2, carbs: 7, fat: 0, confidence: 0, uncertaintyNotes: ""))
        var guessed = edited
        guessed.items[0].calories = 900; guessed.items[0].protein = 90
        guessed.items[1].calories = 700; guessed.items[1].protein = 70
        let result = try FoodReview.preserveCorrections(guessed, baseline: original.items, edited: edited)
        XCTAssertEqual(result.items.map(\.name), ["豆腐", "白菜"])
        XCTAssertEqual(result.items[0].grams, 123)
        XCTAssertEqual(result.items[0].calories, edited.items[0].calories)
        XCTAssertEqual(result.items[0].protein, 11.5)
        XCTAssertEqual(result.items[1], edited.items[1])
        XCTAssertEqual(result.calories, edited.calories)
        XCTAssertEqual(result.protein, edited.protein)
        let baseline = FoodReview.nextCorrectionBaseline(original.items, edited: edited.items, refreshed: result.items)
        XCTAssertNotEqual(baseline.first?.protein, result.items.first?.protein, "Manual corrections remain marked for another analysis")
        guessed.items.append(original.items[1])
        XCTAssertThrowsError(try FoodReview.preserveCorrections(guessed, baseline: original.items, edited: edited))
    }

}
