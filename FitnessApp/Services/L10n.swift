import Foundation

/// Uses iOS bundle language selection; English keys are also the fallback text.
/// User-entered text, database identifiers and API fields do not pass through this helper.
enum L10n {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        return arguments.isEmpty ? format : String(format: format, locale: Locale.current, arguments: arguments)
    }
    static func homeGreeting(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 0..<12: return text("Good morning, Duoduo")
        case 12..<18: return text("Good afternoon, Duoduo")
        default: return text("Good evening, Duoduo")
        }
    }
    static var responseLanguage: String {
        bundle.preferredLocalizations.first?.hasPrefix("zh") == true ? "Simplified Chinese" : "English"
    }
}
