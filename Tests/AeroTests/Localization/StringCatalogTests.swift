import Foundation
import Testing

// AGENTS.md › Internationalization. Command-line builds do not sync the String Catalog, so these slip through
// every build and only show as English text in a French run. Written as failure modes first:
// 1. A literal the interface shows has no catalog entry, so it is never translated.
// 2. An entry has no French translation.
// 3. An entry keeps an English value that differs from its key, so the English interface shows stale text.

struct StringCatalogTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private let entries: [String: [String: Any]]

    init() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("App/Resources/Localizable.xcstrings"))
        let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        entries = try #require(catalog["strings"] as? [String: [String: Any]])
        #expect(!entries.isEmpty, "The catalog contains translations")
    }

    /// Literals passed to the localizing initializers the app uses. Interpolated ones are keyed by format and skipped.
    private var localizedLiteral: Regex<(Substring, Substring)> { /(?:String\(localized: |\bText\(|\bButton\(|\bLabel\(|\bMenu\(|\bSection\(|\bToggle\(|\bPicker\(|\bTextField\(|\.help\(|\.accessibilityLabel\(|LocalizedStringKey\(|LocalizedStringResource\()"((?:[^"\\]|\\.)*)"/ }

    private func localizations(_ key: String) -> [String: Any] { entries[key]?["localizations"] as? [String: Any] ?? [:] }

    @Test func everyShownLiteralHasAnEntry() throws {
        let sources = try #require(FileManager.default.enumerator(at: Self.root.appendingPathComponent("App"), includingPropertiesForKeys: nil))
        var missing: [String] = []
        for case let file as URL in sources where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: localizedLiteral) {
                let literal = String(match.1)
                guard !literal.contains("\\("), literal.contains(where: \.isLetter) else { continue }
                let key = literal.replacing("\\\"", with: "\"").replacing("\\n", with: "\n")
                if entries[key] == nil { missing.append("\(file.lastPathComponent): \(key)") }
            }
        }
        #expect(missing.isEmpty, "Not in Localizable.xcstrings: \(missing)")
    }

    @Test func everyEntryIsInFrench() {
        let untranslated = entries.filter { key, entry in
            entry["shouldTranslate"] as? Bool != false && localizations(key)["fr"] == nil
        }.keys.sorted()
        #expect(untranslated.isEmpty, "No French for: \(untranslated)")
    }

    @Test func englishValuesMatchTheirKey() {
        // A positional value such as "%1$@ of %2$@" is how a format reorders its arguments.
        let stale = entries.keys.filter { key in
            guard let unit = (localizations(key)["en"] as? [String: Any])?["stringUnit"] as? [String: Any],
                  let value = unit["value"] as? String else { return false }
            return value != key && !value.contains("$")
        }.sorted()
        #expect(stale.isEmpty, "English values that no longer match their key: \(stale)")
    }
}
