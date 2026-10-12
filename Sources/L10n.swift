import Foundation

/// Small helper around `NSLocalizedString`.
///
/// Translations live in `Resources/<lang>.lproj/Localizable.strings` and are copied into
/// `Snapboard.app/Contents/Resources` by `scripts/build_app.sh`. The app follows the macOS
/// system language; English is the development language and fallback.
enum L10n {
    /// Returns the localized string for a semantic key such as `"menu.quit"`.
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
    }

    /// Returns the localized format string for `key`, filled with `args`.
    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: args)
    }
}
