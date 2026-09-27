import BrowserCore
import SwiftUI

/// The same space identity in its sidebar, switcher and settings rows.
struct SpaceIcon: View {
    let space: BrowserSpace
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let emoji = space.emoji {
                Text(verbatim: emoji)
                    .font(.system(size: size * 0.85))
                    .fixedSize()
            } else {
                Circle().fill(space.color.tint).frame(width: size * 0.55, height: size * 0.55)
            }
        }
        .frame(width: size, height: size, alignment: .center)
        .accessibilityHidden(true)
    }
}

/// The space's icon on a tile in its color, as the space form shows it.
struct SpaceTile: View {
    let space: BrowserSpace
    var size: CGFloat = 28

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.25)
        Group {
            if let emoji = space.emoji {
                Text(verbatim: emoji).font(.system(size: size * 0.52)).fixedSize()
            } else {
                Circle().fill(.white.opacity(0.9)).frame(width: size * 0.22, height: size * 0.22)
            }
        }
        .frame(width: size, height: size)
        .background(space.color.tint.gradient, in: tile)
        .accessibilityHidden(true)
    }
}
