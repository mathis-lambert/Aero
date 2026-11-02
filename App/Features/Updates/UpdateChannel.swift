import SwiftUI

/// Where the one Aero app takes its updates from (docs/UPDATES.md › Channels): the person's choice, kept in the
/// preferences, never a separate app.
enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable, beta, nightly

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        case .nightly: "Nightly"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .stable: "Tested releases. The right choice for most people."
        case .beta: "Previews of the next version, and every stable release."
        case .nightly: "Every change as soon as it lands. Expect rough edges."
        }
    }

    var symbol: String {
        switch self {
        case .stable: "checkmark.seal"
        case .beta: "testtube.2"
        case .nightly: "moon.stars"
        }
    }
}
