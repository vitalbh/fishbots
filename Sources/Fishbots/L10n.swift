import Foundation

/// The interface language. The Portuguese text is the key (the app was written in Portuguese first); other languages
/// look it up in a table (L10nEnglish.swift). Anything missing shows in Portuguese, and `scripts/l10n-check.sh` lists it.
enum L10n {
    /// "auto" (the Mac's language), "pt" or "en".
    static var setting: String {
        get { UserDefaults.standard.string(forKey: "language") ?? "auto" }
        set {
            UserDefaults.standard.set(newValue, forKey: "language")
            // system-provided text (alert buttons, date formats, the Info.plist permission prompts) follows on the next launch
            if newValue == "auto" { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
            else { UserDefaults.standard.set([newValue == "pt" ? "pt-BR" : "en"], forKey: "AppleLanguages") }
            resolved = resolve()
            onChange?()
        }
    }

    /// The language in use: "pt" or "en".
    private(set) static var resolved = resolve()
    static var isPortuguese: Bool { resolved == "pt" }

    /// The app redraws menus and windows when the language changes.
    static var onChange: (() -> Void)?

    private static func resolve() -> String {
        switch UserDefaults.standard.string(forKey: "language") ?? "auto" {
        case "pt": return "pt"
        case "en": return "en"
        default:
            let first = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return first.hasPrefix("pt") ? "pt" : "en"
        }
    }

    /// For dates and numbers.
    static var locale: Locale { Locale(identifier: isPortuguese ? "pt_BR" : "en_US") }
    /// For the voice that reads and for transcription.
    static var speechLanguage: String { isPortuguese ? "pt-BR" : "en-US" }
}

/// The interface text in the chosen language.
func tr(_ s: String) -> String {
    L10n.isPortuguese ? s : (english[s] ?? s)
}

/// With values: the text uses %@ (text) and %d (numbers), e.g. tr("%@ está esperando você", name).
func tr(_ s: String, _ args: CVarArg...) -> String {
    String(format: tr(s), locale: L10n.locale, arguments: args)
}
