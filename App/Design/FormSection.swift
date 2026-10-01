import SwiftUI

extension BrowserDesign {
    /// The centered column of editing pages: the space form, and profile and space details.
    static let formWidth: CGFloat = 440
    /// Identity tiles and the name field beside them.
    static let identityHeight: CGFloat = 40
}

/// A titled group of an editing page, with an optional secondary action beside the title and an
/// explanation below.
struct FormSection<Content: View, Accessory: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(BrowserDesign.Typography.label)
                    .foregroundStyle(palette.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                accessory
            }
            .frame(minHeight: 22)
            content
            if let footer {
                Text(footer)
                    .font(BrowserDesign.Typography.caption)
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension FormSection where Accessory == EmptyView {
    init(_ title: LocalizedStringKey, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, footer: footer, content: content, accessory: { EmptyView() })
    }
}

extension FormSection {
    init(_ title: LocalizedStringKey, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.init(title: title, footer: footer, content: content, accessory: accessory)
    }
}

/// The small action beside a section title, so it never competes with the section's controls.
struct SectionActionButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void
    @Environment(\.palette) private var palette

    init(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(BrowserDesign.Typography.label)
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.xs))
        }
        .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.xs))
    }
}

extension View {
    /// The large name field beside an identity tile, outlined in `tint` while it is edited.
    func identityField(focused: Bool, tint: Color) -> some View {
        modifier(IdentityField(focused: focused, tint: tint))
    }
}

private struct IdentityField: ViewModifier {
    let focused: Bool
    let tint: Color
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrowserDesign.Radius.control)
        content
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(BrowserDesign.Typography.heading)
            .padding(.horizontal, 10)
            .frame(height: BrowserDesign.identityHeight)
            .background(palette.fill, in: shape)
            .overlay(shape.strokeBorder(focused ? tint : .clear, lineWidth: 1.5))
    }
}
