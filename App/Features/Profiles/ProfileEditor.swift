import AppKit
import BrowserCore
import SwiftUI

/// What a profile editor works on.
enum ProfileTarget: Hashable {
    case create
    case edit(UUID)
}

/// The profile being created or edited: what the editors change, saved only when asked.
struct ProfileDraft {
    /// `nil` while creating.
    var id: UUID?
    var name = ""
    var emoji = ""
    var color = ProfileColor.ocean

    init(_ profile: BrowserProfile? = nil) {
        guard let profile else { return }
        id = profile.id
        name = profile.name
        emoji = profile.emoji ?? ""
        color = profile.color
    }

    var isValid: Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= BrowserProfile.maximumNameLength
    }

    @MainActor func save(in browser: BrowserModel) -> Bool {
        browser.saveProfile(id: id, name: name, color: color, emoji: emoji.isEmpty ? nil : emoji)
    }
}

/// A profile's name, emoji and accent color, as the profile prompt and Settings › Profiles edit them.
struct ProfileFields: View {
    private static let swatchSize: CGFloat = 26
    private static let emojiFieldWidth: CGFloat = 64

    @Binding var draft: ProfileDraft
    @FocusState private var focus: Field?

    private enum Field { case name, emoji }

    /// Rows a grouped form lays out natively, and a prompt stacks.
    var body: some View {
        LabeledContent("Name") {
            TextField("Name", text: $draft.name, prompt: Text("Profile name"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .focused($focus, equals: .name)
                .accessibilityIdentifier("profiles.name")
        }
        LabeledContent("Emoji") {
            HStack(spacing: 2) {
                TextField("Emoji", text: $draft.emoji, prompt: Text("None"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(width: Self.emojiFieldWidth)
                    .focused($focus, equals: .emoji)
                    .onChange(of: draft.emoji) { _, text in keepOneEmoji(text) }
                    .accessibilityIdentifier("profiles.emoji")
                IconButton(symbol: "face.smiling", label: "Show emoji", size: BrowserDesign.navigationButtonSize) {
                    focus = .emoji
                    NSApp.orderFrontCharacterPalette(nil)
                }
            }
        }
        LabeledContent("Accent color") {
            HStack(spacing: 8) {
                ForEach(ProfileColor.allCases, id: \.self) { option in
                    Button { draft.color = option } label: {
                        Circle().fill(option.tint)
                            .frame(width: Self.swatchSize, height: Self.swatchSize)
                            .overlay { if draft.color == option { Image(systemName: "checkmark").font(BrowserDesign.Typography.caption.weight(.bold)).foregroundStyle(.white) } }
                            .padding(3)
                            .overlay(Circle().strokeBorder(draft.color == option ? option.tint : .clear, lineWidth: 1))
                    }
                    .buttonStyle(QuietButtonStyle(radius: Self.swatchSize))
                    .accessibilityLabel(Text(option.label))
                    .accessibilityAddTraits(draft.color == option ? .isSelected : [])
                }
            }
        }
        .onAppear { if draft.name.isEmpty { focus = .name } }
    }

    /// Keeps the last emoji typed or picked, so a new one replaces the old; anything else clears it.
    private func keepOneEmoji(_ text: String) {
        let kept = BrowserProfile.emoji(from: text) ?? text.last.flatMap { BrowserProfile.emoji(from: String($0)) } ?? ""
        if kept != text { draft.emoji = kept }
    }
}

/// Creating or editing a profile from the browser window.
struct ProfilePrompt: View {
    let browser: BrowserModel
    let target: ProfileTarget
    @State private var draft = ProfileDraft()

    var body: some View {
        Prompt(title: Text(draft.id == nil ? "New profile" : "Edit profile"),
               message: Text("Cookies and website sign-ins stay separate for each profile.")) {
            VStack(alignment: .leading, spacing: 12) { ProfileFields(draft: $draft) }
        } actions: {
            PromptCancelButton { browser.dismissPrompt() }
            PromptConfirmButton(title: draft.id == nil ? "Create profile" : "Save changes") {
                if draft.save(in: browser) { browser.dismissPrompt() }
            }
            .disabled(!draft.isValid)
            .accessibilityIdentifier("profiles.save")
        }
        .onAppear {
            if case .edit(let id) = target { draft = ProfileDraft(browser.session.profiles.first { $0.id == id }) }
        }
    }
}
