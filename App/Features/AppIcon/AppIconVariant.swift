import SwiftUI

/// An alternate app icon from `App/Resources/AppIcons`. The stable `id` is what preferences store.
/// The A on paper and on night is the system icon itself (Automatic), so it is not an alternate; it is
/// kept as artwork only, to draw Automatic.
struct AppIconVariant: Hashable, Identifiable, Sendable {
    enum Mark: String, CaseIterable {
        case a, feather

        var label: String {
            switch self {
            case .a: String(localized: "Letter A")
            case .feather: String(localized: "Feather")
            }
        }
    }
    enum Palette: String, CaseIterable {
        case light, dark, blue, bw, wb, lavender, sun, terracotta, olive, dawn, aurora
    }

    let mark: Mark
    let palette: Palette

    static let all: [AppIconVariant] = Mark.allCases.flatMap { mark in
        Palette.allCases.map { AppIconVariant(mark: mark, palette: $0) }
    }.filter { !($0.mark == .a && [.light, .dark].contains($0.palette)) }

    /// The system icon's artwork in one appearance. The system's own rendering cannot stand in: once an
    /// alternate is on the bundle, the system returns that one.
    static func system(dark: Bool) -> AppIconVariant { AppIconVariant(mark: .a, palette: dark ? .dark : .light) }

    var id: String { "\(mark.rawValue)-\(palette.rawValue)" }
    var artwork: NSImage? { Bundle.main.url(forResource: "aero-\(id)", withExtension: "svg").flatMap(NSImage.init(contentsOf:)) }

    /// Returns `nil` for an unknown identifier.
    init?(id: String) {
        guard let variant = Self.all.first(where: { $0.id == id }) else { return nil }
        self = variant
    }

    private init(mark: Mark, palette: Palette) {
        self.mark = mark
        self.palette = palette
    }

    var label: String {
        String(localized: "\(mark.label), \(paletteName)", comment: "App icon variant: mark, then palette, such as “Feather, Sun”.")
    }

    var paletteName: String {
        switch palette {
        case .light: String(localized: "Paper")
        case .dark: String(localized: "Night")
        case .blue: String(localized: "Blue")
        case .bw: String(localized: "Black on white")
        case .wb: String(localized: "White on black")
        case .lavender: String(localized: "Lavender")
        case .sun: String(localized: "Sun")
        case .terracotta: String(localized: "Terracotta")
        case .olive: String(localized: "Olive")
        case .dawn: String(localized: "Dawn")
        case .aurora: String(localized: "Aurora")
        }
    }
}
