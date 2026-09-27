import AppKit
import BrowserCore
import SwiftUI

struct SpaceDraft {
    var id: UUID?
    var name = ""
    var color = SpaceColor.initial
    var emoji = ""
    var profileID: UUID?
    var createsProfile = false
    var profileName = ""

    init(_ space: BrowserSpace? = nil, profileID: UUID? = nil) {
        id = space?.id
        name = space?.name ?? ""
        color = space?.color ?? .initial
        emoji = space?.emoji ?? ""
        self.profileID = space?.profileID ?? profileID
    }

    /// A new space takes the first preset no other space uses, so neighbors stay distinct.
    init(profileID: UUID?, besides spaces: [BrowserSpace]) {
        self.init(profileID: profileID)
        color = SpaceColor.presets.map(\.color).first { color in !spaces.contains { $0.color == color } } ?? .initial
    }

    var isValid: Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= BrowserSpace.maximumNameLength
            && (createsProfile ? !profileName.isEmpty && profileName.count <= BrowserProfile.maximumNameLength : profileID != nil)
    }
}

/// The one form that creates a space and edits it in Settings: its identity as the sidebar shows
/// it, then the profile it browses with. See docs/SPACES.md › Settings and space form.
struct SpaceForm: View {
    private static let choiceSize: CGFloat = 32
    private static let swatchSize: CGFloat = 24
    private static let suggestions = ["💼", "🏠", "📚", "💡", "🎨", "🎮", "🎵", "✈️", "🛒", "💻", "🌱"]

    @Binding var draft: SpaceDraft
    let profiles: [BrowserProfile]
    /// Settings create a profile in their own sheet; without it, the new profile is named inline.
    var createProfile: (() -> Void)?
    /// Return or leaving the name field.
    var commitName: () -> Void = {}
    @FocusState private var focus: Field?
    @Environment(\.palette) private var palette

    private enum Field { case name, emoji, profileName }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            identity
            FormSection("Icon") { icons }
            FormSection("Color") { colors }
            FormSection("Profile", footer: "Cookies, sign-ins and history belong to the profile. Spaces with the same profile share them.") {
                profile
            } accessory: { profileAccessory }
        }
        .onAppear { if draft.name.isEmpty { focus = .name } }
        .onChange(of: focus) { old, new in
            if old == .emoji && new != .emoji { keepOneEmoji() }
            if old == .name && new != .name { commitName() }
        }
    }

    /// The icon doubles as the emoji field: click it to type or paste any emoji.
    private var identity: some View {
        HStack(spacing: 10) {
            let tile = RoundedRectangle(cornerRadius: BrowserDesign.Radius.control)
            ZStack {
                tile.fill(draft.color.tint.gradient)
                if draft.emoji.isEmpty && focus != .emoji {
                    Circle().fill(.white.opacity(0.9)).frame(width: 9, height: 9).accessibilityHidden(true)
                }
                TextField("Emoji", text: $draft.emoji, prompt: Text(verbatim: ""))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(size: 21))
                    .multilineTextAlignment(.center)
                    .focused($focus, equals: .emoji)
                    .onSubmit(keepOneEmoji)
                    .accessibilityIdentifier("spaces.emoji")
            }
            .frame(width: BrowserDesign.identityHeight, height: BrowserDesign.identityHeight)
            .overlay(tile.strokeBorder(focus == .emoji ? .white.opacity(0.8) : palette.line, lineWidth: focus == .emoji ? 2 : 1))
            .contentShape(tile)
            .onTapGesture { focus = .emoji }
            .tooltip(Text("Type or paste an emoji"))

            TextField("Name", text: $draft.name, prompt: Text("Space name"))
                .identityField(focused: focus == .name, tint: draft.color.tint)
                .focused($focus, equals: .name)
                .onSubmit(commitName)
                .accessibilityIdentifier("spaces.name")
        }
        .browserAnimation(value: draft.color)
    }

    private var icons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.choiceSize, maximum: Self.choiceSize), spacing: 6)], alignment: .leading, spacing: 6) {
            choice(selected: draft.emoji.isEmpty, label: Text("No emoji")) {
                Circle().fill(draft.color.tint).frame(width: 9, height: 9)
            } action: { draft.emoji = "" }
            ForEach(Self.suggestions, id: \.self) { emoji in
                choice(selected: draft.emoji == emoji, label: Text(verbatim: emoji)) {
                    Text(verbatim: emoji).font(.system(size: 17))
                } action: { draft.emoji = emoji }
            }
            choice(selected: false, label: Text("More emoji…")) {
                Image(systemName: "face.smiling").font(BrowserDesign.Typography.chrome.weight(.medium)).foregroundStyle(palette.secondary)
            } action: {
                focus = .emoji
                NSApp.orderFrontCharacterPalette(nil)
            }
            .tooltip(Text("More emoji…"))
        }
    }

    private var colors: some View {
        HStack(spacing: 8) {
            ForEach(SpaceColor.presets, id: \.color) { preset in
                swatch(preset.color, name: preset.name, selected: draft.color == preset.color) { draft.color = preset.color }
            }
            customColor
        }
    }

    /// The last swatch: a plus until a custom color is chosen, then that color. A click opens the
    /// system's color popover over it.
    private var customColor: some View {
        let selected = !draft.color.isPreset
        return swatchFace(draft.color, selected: selected) {
            if !selected {
                Circle().fill(palette.fill)
                    .overlay(Circle().strokeBorder(AngularGradient(colors: SpaceColor.presets.map(\.color.tint) + [SpaceColor.initial.tint], center: .center), lineWidth: 2))
                    .overlay { Image(systemName: "plus").font(BrowserDesign.Typography.glyph).foregroundStyle(palette.secondary) }
            }
        }
        .accessibilityHidden(true)
        .overlay { SystemColorPopover(color: draft.color, label: String(localized: "Custom color…")) { draft.color = $0 } }
        .tooltip(Text("Custom color…"))
    }

    private func swatch(_ color: SpaceColor, name: LocalizedStringResource, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { swatchFace(color, selected: selected) }
            .buttonStyle(QuietButtonStyle(radius: Self.swatchSize))
            .tooltip(Text(name))
            .accessibilityLabel(Text(name))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatchFace(_ color: SpaceColor, selected: Bool, @ViewBuilder face: () -> some View = { EmptyView() }) -> some View {
        Circle().fill(color.tint.gradient)
            .overlay { face() }
            .frame(width: Self.swatchSize, height: Self.swatchSize)
            .overlay {
                if selected { Image(systemName: "checkmark").font(BrowserDesign.Typography.glyph).foregroundStyle(.white) }
            }
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? color.tint : .clear, lineWidth: 2))
    }

    @ViewBuilder private var profile: some View {
        if draft.createsProfile {
            TextField("Profile name", text: $draft.profileName, prompt: Text("Profile name"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .profileName)
                .accessibilityIdentifier("spaces.profileName")
        } else {
            Picker("Profile", selection: $draft.profileID) {
                ForEach(profiles) { profile in Text(verbatim: profile.name).tag(Optional(profile.id)) }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("spaces.profile")
        }
    }

    /// A secondary action beside the section title, so it never competes with the picker.
    @ViewBuilder private var profileAccessory: some View {
        if draft.createsProfile {
            SectionActionButton("Choose existing profile", symbol: "arrow.uturn.backward") { draft.createsProfile = false }
        } else {
            SectionActionButton("New profile…", symbol: "plus") {
                if let createProfile { createProfile() } else {
                    draft.createsProfile = true
                    focus = .profileName
                }
            }
            .accessibilityIdentifier("spaces.newProfile")
        }
    }

    private func choice(selected: Bool, label: Text, @ViewBuilder content: () -> some View, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrowserDesign.Radius.control)
        return Button(action: action) {
            content()
                .frame(width: Self.choiceSize, height: Self.choiceSize)
                .background(selected ? AnyShapeStyle(draft.color.tint.opacity(0.22)) : AnyShapeStyle(palette.fill), in: shape)
                .overlay(shape.strokeBorder(selected ? draft.color.tint : .clear, lineWidth: 1.5))
                .contentShape(shape)
        }
        .buttonStyle(QuietButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Keeps the last emoji typed or picked, so a new one replaces the old; anything else clears it.
    private func keepOneEmoji() {
        let text = draft.emoji
        let kept = BrowserSpace.emoji(from: text) ?? text.last.flatMap { BrowserSpace.emoji(from: String($0)) } ?? ""
        if kept != text { draft.emoji = kept }
    }
}

/// A transparent color well over the swatch beneath it: a click opens the system's color popover
/// (its minimal style), which offers the full color panel from there. A view with zero alpha still
/// takes clicks and anchors the popover.
private struct SystemColorPopover: NSViewRepresentable {
    let color: SpaceColor
    let label: String
    let onChange: (SpaceColor) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSColorWell {
        let well = SwatchSizedColorWell(style: .minimal)
        well.alphaValue = 0
        well.supportsAlpha = false
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.setAccessibilityIdentifier("spaces.customColor")
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.onChange = onChange
        well.setAccessibilityLabel(label)
        if SpaceColor(well.color) != color { well.color = color.nsColor }
    }

    /// A closed form must not keep receiving the shared panel's colors.
    static func dismantleNSView(_ well: NSColorWell, coordinator: Coordinator) {
        well.deactivate()
        well.target = nil
    }

    @MainActor final class Coordinator: NSObject {
        var onChange: (SpaceColor) -> Void = { _ in }

        @objc func colorChanged(_ well: NSColorWell) {
            if let color = SpaceColor(well.color) { onChange(color) }
        }
    }

    /// Takes the swatch's size rather than the well's own.
    private final class SwatchSizedColorWell: NSColorWell {
        override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    }
}
