import Foundation

/// Localização: as chaves são o texto em português (idioma-base); os demais idiomas vêm de Resources/*.lproj.
/// `L("texto")` devolve a tradução; `L("… %@ …", arg)` formata.
func L(_ key: String) -> String {
    L10n.bundle.localizedString(forKey: key, value: key, table: nil)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: args)
}

enum L10n {
    static let changed = Notification.Name("SnapLensLanguageChanged")
    static let defaultsKey = "appLanguage"

    /// Idiomas suportados pelo app (código do .lproj → nome nativo).
    static let languages: [(code: String, name: String)] = [
        ("pt-BR", "Português (Brasil)"), ("en", "English"), ("es", "Español"), ("it", "Italiano"), ("zh-Hans", "中文（简体）"),
    ]

    /// "system" = seguir o idioma do macOS.
    static var selection: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? "system" }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            cached = nil
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /// Código efetivo em uso.
    static var code: String {
        if selection != "system" { return selection }
        let preferred = Bundle.main.preferredLocalizations.first ?? "pt-BR"
        return languages.contains { $0.code == preferred } ? preferred : "pt-BR"
    }

    nonisolated(unsafe) private static var cached: Bundle?
    static var bundle: Bundle {
        if let cached { return cached }
        let b = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
        cached = b
        return b
    }

    /// Locale para datas/números coerente com o idioma do app.
    static var locale: Locale { Locale(identifier: code == "zh-Hans" ? "zh_Hans" : code.replacingOccurrences(of: "-", with: "_")) }
}
