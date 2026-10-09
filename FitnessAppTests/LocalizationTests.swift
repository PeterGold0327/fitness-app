import XCTest
import Foundation
#if SWIFT_PACKAGE
@testable import FitnessCore
#else
@testable import LeanLog
#endif

final class LocalizationTests: XCTestCase {
    private func localizedBundle(_ language: String) throws -> Bundle {
        let root = try XCTUnwrap(L10n.bundle.resourceURL)
        let exact = root.appendingPathComponent(language + ".lproj")
        // SwiftPM normalizes localization directory names to lowercase on Linux.
        let url = FileManager.default.fileExists(atPath: exact.path) ? exact : root.appendingPathComponent(language.lowercased() + ".lproj")
        return try XCTUnwrap(Bundle(url: url))
    }
    private func strings(_ language: String) throws -> [String: String] {
        let bundle = try localizedBundle(language)
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        // Xcode can compile .strings to a binary plist; SwiftPM copies the UTF-8 source.
        if let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] {
            return values
        }
        let source = try XCTUnwrap(String(data: data, encoding: .utf8))
        let regex = try NSRegularExpression(pattern: #"("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;"#)
        var values: [String: String] = [:]
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let key = try JSONDecoder().decode(String.self, from: Data(source[Range(match.range(at: 1), in: source)!].utf8))
            let value = try JSONDecoder().decode(String.self, from: Data(source[Range(match.range(at: 2), in: source)!].utf8))
            XCTAssertNil(values[key], "Duplicate localization key: \(key)")
            values[key] = value
        }
        return values
    }
    func testChineseBundleContainsRealTranslationsForAllFiveTabs() throws {
        let chinese = try localizedBundle("zh-Hans")
        for (key, expected) in [("Home", "首页"), ("Nutrition", "营养"), ("Training", "运动"),
                                ("Progress", "进展"), ("Settings", "设置")] {
            XCTAssertEqual(chinese.localizedString(forKey: key, value: key, table: "Localizable"), expected)
        }
    }
    func testEnglishAndChineseHaveIdenticalNonemptyKeysAndFormatArguments() throws {
        let english = try strings("en"), chinese = try strings("zh-Hans")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        for (key, translation) in chinese {
            XCTAssertFalse(translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
            XCTAssertEqual(english[key], key, "English remains the fallback")
            XCTAssertEqual(key.components(separatedBy: "%@").count, translation.components(separatedBy: "%@").count, key)
        }
    }
    func testChineseNutritionFormatPreservesValuesAndTranslatesUnits() throws {
        let chinese = try localizedBundle("zh-Hans")
        let key = "Remaining: %@ kcal · %@ g protein"
        let format = chinese.localizedString(forKey: key, value: key, table: "Localizable")
        XCTAssertEqual(String(format: format, locale: Locale(identifier: "zh-Hans"), arguments: ["1700", "90"]),
                       "剩余：1700 千卡 · 蛋白质 90 克")
    }
    func testWeeklySummaryFormatsEveryFieldAndKeepsLineBreaks() throws {
        let chinese = try localizedBundle("zh-Hans")
        let key = "Last 7 calendar days\nNutrition recorded on %@/7 days\nAverage on logged days: %@ kcal · %@ g protein\nManually logged gym sessions: %@\nBadminton: %@\nAverage sleep (available nights): %@\nWeight: %@\n%@\n%@\n%@"
        let format = chinese.localizedString(forKey: key, value: key, table: "Localizable")
        let result = String(format: format, locale: Locale(identifier: "zh-Hans"), arguments:
                            ["5", "2600", "130", "3", "日期", "8 小时", "符合目标", "体重建议", "训练量建议", "动作建议"])
        XCTAssertTrue(result.contains("饮食记录天数：5/7 天"))
        XCTAssertTrue(result.contains("2600 千卡 · 蛋白质 130 克"))
        XCTAssertTrue(result.contains("力量训练：3 次"))
        XCTAssertTrue(result.hasSuffix("体重建议\n训练量建议\n动作建议"))
        XCTAssertFalse(result.contains("%@"))
    }
    func testUnknownUserTextIsNotTranslatedOrTreatedAsAFormatString() {
        XCTAssertEqual(L10n.text("My own lunch: 50% vegetables"), "My own lunch: 50% vegetables")
    }
    func testChineseCoachingAndPermissionMessagesExist() throws {
        let chinese = try localizedBundle("zh-Hans")
        for key in ["Keep calories the same. Aim for roughly 0.1–0.25 kg/week.",
                    "Target reps completed at manageable RPE. Consider adding 1–2.5 kg next session.",
                    "Connect Apple Health in Settings. Read permissions are optional per data type.",
                    "The photo could not reach the AI service. Check your connection or enter the meal manually."] {
            let translated = chinese.localizedString(forKey: key, value: key, table: "Localizable")
            XCTAssertNotEqual(translated, key)
            XCTAssertFalse(translated.isEmpty)
        }
    }
    func testGrowthTimelineTerminologyInEnglishAndSimplifiedChinese() throws {
        let chinese = try localizedBundle("zh-Hans"), english = try localizedBundle("en")
        for (key, translation) in [("Growth Timeline", "成长时间线"), ("Milestones", "里程碑"),
                                    ("Progress Photos", "成长照片"), ("On This Day", "那年今日"),
                                    ("Export Archive", "导出成长档案")] {
            XCTAssertEqual(chinese.localizedString(forKey: key, value: key, table: "Localizable"), translation)
            XCTAssertEqual(english.localizedString(forKey: key, value: key, table: "Localizable"), key)
        }
    }
    func testChineseTimelineSummaryFormatsAllValues() throws {
        let chinese = try localizedBundle("zh-Hans")
        let key = "Nutrition recorded on %@/%@ days; averages on logged days: %@ kcal · %@ g protein. Gym: %@ sessions; badminton: %@ days. Sleep: %@ h across %@ nights. Both nutrition targets met on %@ logged days."
        let format = chinese.localizedString(forKey: key, value: key, table: "Localizable")
        let result = String(format: format, arguments: ["5", "7", "2700", "130", "3", "2", "7.5", "6", "4"])
        XCTAssertTrue(result.contains("5/7 天")); XCTAssertTrue(result.contains("2700 千卡"))
        XCTAssertTrue(result.contains("力量训练：3 次")); XCTAssertTrue(result.contains("平均 7.5 小时，共 6 晚"))
        XCTAssertTrue(result.contains("4 个已记录日")); XCTAssertFalse(result.contains("%@"))
    }

    func testHomeGreetingUsesLocalTimeAtNoonAndEveningBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Australia/Brisbane"))
        for (hour, minute, second, key) in [
            (0, 0, 0, "Good morning, Duoduo"),
            (11, 59, 59, "Good morning, Duoduo"),
            (12, 0, 0, "Good afternoon, Duoduo"),
            (17, 59, 59, "Good afternoon, Duoduo"),
            (18, 0, 0, "Good evening, Duoduo"),
            (23, 59, 59, "Good evening, Duoduo")
        ] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: hour, minute: minute, second: second)))
            XCTAssertEqual(L10n.homeGreeting(at: date, calendar: calendar), L10n.text(key))
        }
        let localNoon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12)))
        var utc = calendar; utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertEqual(L10n.homeGreeting(at: localNoon, calendar: utc), L10n.text("Good morning, Duoduo"))
        XCTAssertEqual(L10n.homeGreeting(at: localNoon, calendar: calendar), L10n.text("Good afternoon, Duoduo"))
    }
    func testHomeGreetingTranslationsUseTheRequestedNickname() throws {
        let english = try strings("en"), chinese = try strings("zh-Hans")
        for (key, translation) in [("Good morning, Duoduo", "早上好，多多"),
                                   ("Good afternoon, Duoduo", "下午好，多多"),
                                   ("Good evening, Duoduo", "晚上好，多多")] {
            XCTAssertEqual(english[key], key)
            XCTAssertEqual(chinese[key], translation)
        }
    }

}
