import Foundation
import Combine

enum Lang: String, CaseIterable, Identifiable {
    case en
    case fr
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .en: return "English"
        case .fr: return "Français"
        }
    }
    var code: String { rawValue.uppercased() }
}

@MainActor
final class AppLanguage: ObservableObject {
    @Published var current: Lang

    /// Active display skin. Publishing it re-renders every localized view
    /// (they all observe this object) and the `didSet` keeps the static
    /// `RetroTheme.kind` — which the palette accessors read — in step.
    @Published var themeKind: ThemeKind = .retro {
        didSet { RetroTheme.kind = themeKind }
    }

    init(initial: Lang = AppLanguage.detect()) {
        self.current = initial
        // Optional launch override: `-theme iso|hmi|retro` (used to capture
        // each skin headlessly, since UI automation is TCC-blocked). Property
        // observers don't fire during init, so sync RetroTheme explicitly.
        if let i = CommandLine.arguments.firstIndex(of: "-theme"),
           CommandLine.arguments.indices.contains(i + 1) {
            let v = CommandLine.arguments[i + 1].lowercased()
            if v.hasPrefix("iso") || v == "hmi" { themeKind = .iso101 }
        }
        RetroTheme.kind = themeKind
    }

    /// Flip between the retro phosphor and ISA-101 high-performance skins.
    func toggleTheme() {
        themeKind = (themeKind == .retro) ? .iso101 : .retro
    }

    nonisolated private static func detect() -> Lang {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("fr") ? .fr : .en
    }

    func t(_ key: String) -> String {
        Strings.lookup(key, lang: current)
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let raw = Strings.lookup(key, lang: current)
        return String(format: raw, arguments: args)
    }

    func cycle() {
        let all = Lang.allCases
        guard let idx = all.firstIndex(of: current) else { return }
        current = all[(idx + 1) % all.count]
    }
}
