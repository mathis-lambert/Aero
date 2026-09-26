import BrowserCore
import SwiftUI

/// One icon per profile in the sidebar's footer: its emoji, or a dot in its color.
struct ProfileBar: View {
    private static let iconSize: CGFloat = 24
    private static let dotSize: CGFloat = 7
    private static let emojiFont = Font.system(size: 13)

    let browser: BrowserModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(browser.session.profiles) { profile in
                icon(profile, selected: profile.id == browser.window.selectedProfileID)
            }
        }
    }

    private func icon(_ profile: BrowserProfile, selected: Bool) -> some View {
        Button { browser.switchProfile(profile.id) } label: {
            Group {
                if let emoji = profile.emoji {
                    Text(verbatim: emoji).font(Self.emojiFont)
                        .opacity(selected ? 1 : 0.5)
                } else {
                    Circle().fill(profile.color.tint)
                        .frame(width: Self.dotSize, height: Self.dotSize)
                        .opacity(selected ? 1 : 0.4)
                }
            }
            .frame(width: Self.iconSize, height: Self.iconSize)
            .background(selected ? palette.fill : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        }
        .buttonStyle(QuietButtonStyle())
        .help(Text(verbatim: profile.name))
        .accessibilityLabel(Text(verbatim: profile.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.profile")
        .contextMenu {
            Button("Edit profile…", systemImage: "pencil") { browser.window.profileSheet = .edit(profile.id) }
        }
    }
}

