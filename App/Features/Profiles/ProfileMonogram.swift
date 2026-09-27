import SwiftUI

/// A profile's initial on a neutral disc: profiles have no color of their own; their spaces do.
struct ProfileMonogram: View {
    let name: String
    var size: CGFloat = 28
    @Environment(\.palette) private var palette

    var body: some View {
        Text(verbatim: name.first.map { String($0).localizedUppercase } ?? "")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(palette.ink)
            .frame(width: size, height: size)
            .background(palette.pressed, in: Circle())
            .overlay(Circle().strokeBorder(palette.line))
            .accessibilityHidden(true)
    }
}
