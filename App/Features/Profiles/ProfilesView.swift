import AppKit
import BrowserCore
import SwiftUI

/// What the profile sheet opens on.
enum ProfileSheet: Hashable, Identifiable {
    case create
    case edit(UUID)

    var id: Self { self }
}

struct ProfilesView: View {
    private static let listWidth: CGFloat = 185
    private static let swatchSize: CGFloat = 26
    private static let emojiFieldWidth: CGFloat = 64

    let browser: BrowserModel
    let sheet: ProfileSheet
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var emoji = ""
    @State private var color: ProfileColor = .terracotta
    @FocusState private var focus: Field?
    @Environment(\.palette) private var palette

    private enum Field { case name, emoji }

    private var creating: Bool { editingID == nil }
    private var valid: Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= BrowserProfile.maximumNameLength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your profiles").font(BrowserDesign.Typography.title)
                    Text("Separate spaces for different sides of your day.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                IconButton(symbol: "xmark", label: "Done") { dismiss() }
            }
            HStack(alignment: .top, spacing: 24) {
                list.frame(width: Self.listWidth)
                Hairline(axis: .vertical)
                details.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
        .frame(width: 640, height: 400)
        .onAppear {
            switch sheet {
            case .create: startCreating()
            case .edit(let id): if let profile = browser.session.profiles.first(where: { $0.id == id }) { edit(profile) }
            }
        }
        .onExitCommand { dismiss() }
    }

    private var list: some View {
        VStack(spacing: 6) {
            ForEach(browser.session.profiles) { profile in
                Button { edit(profile) } label: {
                    HStack(spacing: 10) {
                        ProfileBadge(profile: profile)
                        Text(verbatim: profile.name).lineLimit(1)
                        Spacer()
                        if profile.id == browser.window.selectedProfileID {
                            Image(systemName: "checkmark").font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(editingID == profile.id ? palette.fill : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                    .contentShape(Rectangle())
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("profiles.row.\(profile.name)")
            }
            Button(action: startCreating) {
                Label("Add profile", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityIdentifier("profiles.add")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(creating ? "New profile" : "Profile details").font(.headline)
            HStack(alignment: .bottom, spacing: 12) {
                field("Name") {
                    TextField("Profile name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .name)
                        .accessibilityIdentifier("profiles.name")
                }
                field("Emoji") {
                    HStack(spacing: 2) {
                        TextField("None", text: $emoji)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .frame(width: Self.emojiFieldWidth)
                            .focused($focus, equals: .emoji)
                            .onChange(of: emoji) { _, text in keepOneEmoji(text) }
                            .accessibilityIdentifier("profiles.emoji")
                        IconButton(symbol: "face.smiling", label: "Show emoji", size: BrowserDesign.navigationButtonSize) {
                            focus = .emoji
                            NSApp.orderFrontCharacterPalette(nil)
                        }
                    }
                }
            }
            field("Accent color") {
                HStack(spacing: 12) {
                    ForEach(ProfileColor.allCases, id: \.self) { option in
                        Button { color = option } label: {
                            Circle().fill(option.tint)
                                .frame(width: Self.swatchSize, height: Self.swatchSize)
                                .overlay { if color == option { Image(systemName: "checkmark").font(BrowserDesign.Typography.caption.weight(.bold)).foregroundStyle(.white) } }
                                .padding(3)
                                .overlay(Circle().strokeBorder(color == option ? option.tint : .clear, lineWidth: 1))
                        }
                        .buttonStyle(QuietButtonStyle(radius: Self.swatchSize))
                        .accessibilityLabel(Text(option.label))
                        .accessibilityAddTraits(color == option ? .isSelected : [])
                    }
                }
            }
            Label("Cookies and website sign-ins stay separate for each profile.", systemImage: "lock.shield")
                .font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            HStack {
                if let id = editingID, id != browser.window.selectedProfileID {
                    Button("Use profile") { browser.switchProfile(id); dismiss() }
                        .accessibilityIdentifier("profiles.use")
                }
                Spacer()
                Button(creating ? "Create profile" : "Save changes") {
                    if browser.saveProfile(id: editingID, name: name, color: color, emoji: emoji.isEmpty ? nil : emoji) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!valid)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("profiles.save")
            }
        }
    }

    private func field(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
            content()
        }
    }

    /// Keeps the last emoji typed or picked, so a new one replaces the old; anything else clears it.
    private func keepOneEmoji(_ text: String) {
        let kept = BrowserProfile.emoji(from: text) ?? text.last.flatMap { BrowserProfile.emoji(from: String($0)) } ?? ""
        if kept != text { emoji = kept }
    }

    private func edit(_ profile: BrowserProfile) {
        editingID = profile.id
        name = profile.name
        emoji = profile.emoji ?? ""
        color = profile.color
    }

    private func startCreating() {
        editingID = nil
        name = ""
        emoji = ""
        color = .ocean
        focus = .name
    }
}
