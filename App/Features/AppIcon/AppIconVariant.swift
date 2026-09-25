import SwiftUI

/// An alternate app icon from `App/Resources/AppIcons`. The stable `id` is what preferences store.
/// The A on paper and on night is the system icon itself (Automatic), so it is not an alternate.
struct AppIconVariant: Hashable, Identifiable {
    enum Mark: String, CaseIterable { case a, plume }
    enum Palette: String, CaseIterable {
        case light, dark, blue, bw, wb, lavender, sun, terracotta, olive, dawn, aurora
    }

    let mark: Mark
    let palette: Palette

    static let all: [AppIconVariant] = Mark.allCases.flatMap { mark in
        Palette.allCases.map { AppIconVariant(mark: mark, palette: $0) }
    }.filter { !($0.mark == .a && [.light, .dark].contains($0.palette)) }

    var id: String { "\(mark.rawValue)-\(palette.rawValue)" }
    var resourceName: String { "aero-\(id)" }

    /// Returns `nil` for an unknown identifier, such as one saved by a build that had other variants.
    init?(id: String) {
        guard let variant = Self.all.first(where: { $0.id == id }) else { return nil }
        self = variant
    }

    private init(mark: Mark, palette: Palette) {
        self.mark = mark
        self.palette = palette
    }

    var label: String {
        String(localized: "\(markName), \(paletteName)", comment: "App icon variant: mark, then palette, such as “Feather, Sun”.")
    }

    private var markName: String {
        switch mark {
        case .a: String(localized: "Letter A")
        case .plume: String(localized: "Feather")
        }
    }

    private var paletteName: String {
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
