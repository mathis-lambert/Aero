import AppKit
import BrowserCore
import BrowserStorage
import SwiftUI

/// The words of each step, on the plate. Titles use the brand's face; everything else is the browser's own
/// controls and type. See docs/ONBOARDING.md › Steps.
struct OnboardingStepView: View {
    let browser: BrowserModel
    let onboarding: OnboardingModel
    @Binding var ripple: WindRipple?
    @Environment(\.palette) private var palette

    var body: some View {
        switch onboarding.step {
        case .welcome: welcome
        case .source: source
        case .choice: choice
        case .importing: importing
        case .gettingAround: gettingAround
        case .defaultBrowser: defaultBrowser
        case .ready: ready
        }
    }

    // MARK: - Steps

    /// What Aero is, then what the next minute holds, so Get started is an informed choice.
    private var welcome: some View {
        // Centered in the card, a little above the middle, clear of the footer.
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Eyebrow("Welcome to Aero")
            Headline("Light as air.", large: true)
            BodyText("Setup takes about a minute.")
            VStack(alignment: .leading, spacing: 2) {
                WelcomeRow(symbol: "square.and.arrow.down", title: "Bring your things", detail: importPromise) {
                    BrowserIconStack(sources: onboarding.sources)
                }
                WelcomeRow(symbol: "command", title: "Learn the essentials", detail: Text("Four shortcuts to try.")) { EmptyView() }
                WelcomeRow(symbol: "link", title: "Your default browser", detail: Text("Only if you want.")) { EmptyView() }
            }
            .padding(.horizontal, -BrowserDesign.rowInset)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.plan")
            Spacer(minLength: 24)
            Spacer(minLength: 0)
        }
    }

    /// The browsers found are the icons beside it.
    private var importPromise: Text {
        onboarding.sources.isEmpty ? Text("Or start fresh.") : Text("Favorites, history and passwords.")
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Bring your things")
            Headline("Start where you left off.")
            BodyText("Aero copies what you pick. The other browser stays as it is.")
            FormSection("Found on this Mac") {
                VStack(spacing: 2) {
                    if onboarding.sources.isEmpty {
                        Text("No other browser on this Mac.").font(BrowserDesign.Typography.chrome).foregroundStyle(palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, BrowserDesign.rowInset).padding(.vertical, 8)
                    }
                    ForEach(onboarding.sources) { source in
                        SourceRow(source: source, detail: detail(for: source), selected: onboarding.selectedSourceID == source.id) {
                            choose(source.id)
                        }
                        .onboardingFrame("source.\(source.id)", in: onboarding)
                    }
                    SourceRow(source: nil, detail: Text("You can import later from the File menu."), selected: onboarding.selectedSourceID == nil) {
                        choose(nil)
                    }
                    .onboardingFrame("source.fresh", in: onboarding)
                }
                .padding(.horizontal, -BrowserDesign.rowInset)
            }
            if let failure = onboarding.readFailure { Failure(text: failure) }
        }
    }

    /// Selecting a browser sends a ripple across the wind from its row.
    private func choose(_ id: String?) {
        onboarding.select(id)
        if let frame = onboarding.frames["source.\(id ?? "fresh")"] { ripple = WindRipple(origin: CGPoint(x: frame.maxX, y: frame.midY), strength: 0.8) }
    }

    private func detail(for source: ImportSource) -> Text {
        if source.kind == .safari, !source.isReadable { return Text("\(Image(systemName: "lock.fill")) Needs Full Disk Access") }
        guard let profiles = onboarding.previews[source.id] else {
            return onboarding.readingSourceID == source.id ? Text("Looking…") : source.kind == .safari ? Text("Favorites and history") : Text("\(source.profiles.count) profiles")
        }
        let spaces = profiles.reduce(0) { $0 + $1.spaces.count }
        let favorites = profiles.reduce(0) { total, profile in total + profile.spaces.reduce(0) { $0 + $1.allLinks.count } }
        let pages = profiles.reduce(0) { $0 + $1.history.pages.count }
        guard source.favorites != .unreadable else { return Self.joined([Text("\(profiles.count) profiles"), Text("\(pages) pages")]) }
        return Self.joined([Text("\(spaces) spaces"), Text("\(favorites) favorites"), Text("\(pages) pages")])
    }

    /// Counts side by side, each a complete phrase of its own.
    static func joined(_ parts: [Text]) -> Text {
        parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) { Text("\($0) · \($1)") }
    }

    /// A switch for each kind this browser can give. See docs/ONBOARDING.md › Sources.
    private var choice: some View {
        let source = onboarding.source
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow("What comes along")
            Headline("Choose what to bring.")
            FormSection("From \(onboarding.source?.shortName ?? "")", footer: "Open tabs stay behind, and sites will ask you to sign in again.") {
                VStack(spacing: 2) {
                    switch source?.favorites {
                    case .spaces:
                        ChoiceRow(symbol: "star", title: "Spaces and favorites", detail: "Pinned tabs and folders, in their spaces.", isOn: binding(\.favorites))
                    case .bookmarks, nil:
                        ChoiceRow(symbol: "star", title: "Favorites", detail: "Bookmarks become favorites; each folder becomes a group.", isOn: binding(\.favorites))
                    case .unreadable:
                        EncryptedRow(browser: source?.shortName ?? "")
                    }
                    ChoiceRow(symbol: "clock", title: "History", detail: "The control bar knows where you go.", isOn: binding(\.history))
                    if source?.importsPasswords == true {
                        ChoiceRow(symbol: "key", title: "Passwords", detail: "macOS asks you once to allow it.", isOn: binding(\.passwords))
                    }
                }
                .padding(.horizontal, -BrowserDesign.rowInset)
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ImportChoice, Bool>) -> Binding<Bool> {
        Binding { onboarding.choice[keyPath: keyPath] } set: { onboarding.choice[keyPath: keyPath] = $0 }
    }

    private var importing: some View {
        let outcome = onboarding.outcome ?? ImportOutcome()
        let done = !onboarding.isImporting
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let source = onboarding.source {
                    BrowserIcon(bundleIdentifier: source.bundleIdentifier).frame(width: 34, height: 34).onboardingFrame("source.icon", in: onboarding)
                }
                ImportTrail(active: onboarding.isImporting)
                Image(nsImage: AppIconImage.current).resizable().frame(width: 34, height: 34)
            }
            .padding(.bottom, 22)
            .accessibilityHidden(true)
            Eyebrow("Importing")
            Headline(done ? "Everything is here." : "Bringing it over.")
                .id(done)
            VStack(spacing: 2) {
                if onboarding.source?.favorites == .unreadable {
                    ResultRow(symbol: "square.stack", text: Text("\(outcome.spaces) spaces"), state: done || outcome.spaces > 0 ? .done : .busy)
                } else if onboarding.choice.favorites {
                    ResultRow(symbol: "star", text: Self.joined([Text("\(outcome.spaces) spaces"), Text("\(outcome.favorites) favorites")]),
                              state: done || outcome.favorites > 0 ? .done : .busy)
                }
                if onboarding.choice.history {
                    ResultRow(symbol: "clock", text: Text("\(outcome.historyPages) pages of history"), state: done ? .done : .busy)
                }
                // Shown while passwords are being read and once they are; hidden when none were read.
                if onboarding.choice.passwords, onboarding.source?.importsPasswords == true, !(done && outcome.passwords == nil) {
                    let passwords = outcome.passwords
                    ResultRow(symbol: "key", text: passwords.map { Text("\($0.added + $0.present) passwords") } ?? Text("Passwords"),
                              state: passwords?.failure != nil ? .failed : passwords != nil ? .done : .busy)
                    if let failure = passwords?.failure { Failure(text: failure) }
                }
            }
            .padding(.horizontal, -BrowserDesign.rowInset)
            if let failure = outcome.failure { Failure(text: failure) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.importing")
    }

    private var gettingAround: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Getting around")
                .background(TwoFingerSwipe { browser.perform($0 > 0 ? .nextSpace : .previousSpace) })
            Headline("Within reach.")
            BodyText("Try them now.")
            VStack(spacing: 2) {
                ShortcutRow(shortcut: browser.shortcuts.shortcut(for: .nextSpace), label: "Switch spaces", alternative: "Or swipe with two fingers",
                            done: onboarding.triedShortcuts.contains(.nextSpace) || onboarding.triedShortcuts.contains(.previousSpace)) {
                    browser.perform(.nextSpace)
                }
                ShortcutRow(shortcut: browser.shortcuts.shortcut(for: .commandPalette), label: "Open the control bar", done: onboarding.triedShortcuts.contains(.commandPalette)) {
                    browser.perform(.commandPalette)
                }
                ShortcutRow(shortcut: browser.shortcuts.shortcut(for: .toggleSidebar), label: "Show or hide the sidebar", done: onboarding.triedShortcuts.contains(.toggleSidebar)) {
                    browser.perform(.toggleSidebar)
                }
                ShortcutRow(shortcut: browser.shortcuts.shortcut(for: .recentTab), label: "Go back to your last tab", done: onboarding.triedShortcuts.contains(.recentTab)) {
                    browser.perform(.recentTab)
                }
            }
            .padding(.horizontal, -BrowserDesign.rowInset)
        }
    }

    private var defaultBrowser: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Default browser")
            Headline("Links open here.")
            BodyText("From Mail, Messages or a PDF.")
            if onboarding.isDefaultBrowser {
                Label("Aero is your default browser.", systemImage: "checkmark")
                    .font(BrowserDesign.Typography.chrome.weight(.medium))
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("onboarding.isDefault")
            } else {
                Text("macOS asks you to confirm.").font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary)
            }
        }
    }

    private var ready: some View {
        let favorites = browser.session.tabs.filter(\.isFavorite).count
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Ready")
            Headline("Fair winds.", large: true)
            // The person's own shortcut, which they may have changed.
            let newTab = browser.shortcuts.shortcut(for: .newTab)?.keys.joined() ?? BrowserCommand.newTab.title
            BodyText(favorites > 0 ? "Your favorites are in the sidebar. Press \(newTab) to open a new tab." : "Press \(newTab) to open your first tab.")
        }
    }
}

// MARK: - Plate pieces

/// Text that acts, without a button's surface: secondary at rest, ink under the pointer.
struct QuietLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { QuietLink(configuration: configuration) }

    private struct QuietLink: View {
        let configuration: Configuration
        @State private var hovered = false
        @Environment(\.palette) private var palette
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(BrowserDesign.Typography.label)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(hovered && isEnabled ? palette.ink : palette.secondary)
                .opacity(configuration.isPressed ? 0.6 : isEnabled ? 1 : 0.4)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
                .animation(BrowserDesign.hover, value: hovered)
        }
    }
}

/// One thing the onboarding will do, as the welcome lists them.
private struct WelcomeRow<Accessory: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: Text
    @ViewBuilder var accessory: Accessory
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(BrowserDesign.Typography.chrome.weight(.medium))
                detail.font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, BrowserDesign.rowInset)
        .frame(height: 44)
        .accessibilityElement(children: .combine)
    }
}

/// The browsers found on this Mac, their icons overlapping like a small stack.
private struct BrowserIconStack: View {
    let sources: [ImportSource]

    var body: some View {
        HStack(spacing: -5) {
            ForEach(Array(sources.prefix(4).enumerated()), id: \.element.id) { index, source in
                BrowserIcon(bundleIdentifier: source.bundleIdentifier)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .zIndex(Double(-index))
            }
        }
        .accessibilityHidden(true)
    }
}

struct Eyebrow: View {
    let text: LocalizedStringKey
    @Environment(\.palette) private var palette
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).font(BrowserDesign.Typography.label).foregroundStyle(palette.secondary).padding(.bottom, 12)
    }
}

struct BodyText: View {
    let text: LocalizedStringKey
    @Environment(\.palette) private var palette
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).font(BrowserDesign.Typography.field).lineSpacing(3).foregroundStyle(palette.secondary)
            .frame(maxWidth: 340, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 20)
    }
}

private struct Failure: View {
    let text: String
    @Environment(\.palette) private var palette
    var body: some View {
        Text(text).font(BrowserDesign.Typography.caption).foregroundStyle(palette.miss)
            .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
    }
}

/// A row with an icon, a title and a detail, as Settings lists draw them.
private struct OnboardingRow<Accessory: View>: View {
    let icon: AnyView
    let title: Text
    let detail: Text?
    @ViewBuilder var accessory: Accessory
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                title.font(BrowserDesign.Typography.chrome.weight(.medium))
                detail?.font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, BrowserDesign.rowInset)
        .frame(minHeight: 42)
    }
}

/// A browser, or Start fresh; the selected one is filled.
private struct SourceRow: View {
    let source: ImportSource?
    let detail: Text
    let selected: Bool
    let select: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: select) {
            OnboardingRow(icon: icon, title: source.map { Text(verbatim: $0.name) } ?? Text("Start fresh"), detail: detail) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.line))
            }
            .background(selected ? palette.fill : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        }
        .buttonStyle(QuietButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("onboarding.source.\(source?.name ?? "fresh")")
    }

    private var icon: AnyView {
        if let source { return AnyView(BrowserIcon(bundleIdentifier: source.bundleIdentifier)) }
        return AnyView(Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(palette.secondary))
    }
}

private struct ChoiceRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var isOn: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        OnboardingRow(icon: AnyView(Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(palette.secondary)), title: Text(title), detail: Text(detail)) {
            Toggle(isOn: $isOn) { Text(title) }.toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }
}

/// What a browser keeps encrypted, said instead of offered.
private struct EncryptedRow: View {
    let browser: String
    @Environment(\.palette) private var palette

    var body: some View {
        OnboardingRow(icon: AnyView(Image(systemName: "lock").font(.system(size: 14)).foregroundStyle(palette.secondary)),
                      title: Text("Spaces and favorites stay in \(browser)"),
                      detail: Text("\(browser) encrypts them so no other app can read them. Each of its profiles becomes a space.")) { EmptyView() }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onboarding.encrypted")
    }
}

private struct ResultRow: View {
    enum State { case busy, done, failed }
    let symbol: String
    let text: Text
    let state: State
    @Environment(\.palette) private var palette

    var body: some View {
        OnboardingRow(icon: AnyView(Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(palette.secondary)),
                      title: text.monospacedDigit(), detail: nil) {
            switch state {
            case .busy: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tint)
            case .failed: Image(systemName: "exclamationmark.circle").foregroundStyle(palette.miss)
            }
        }
        .contentTransition(.numericText())
        .browserAnimation(value: state == .done)
    }
}

/// A command and the shortcut it has now, which the person may have changed or turned off.
private struct ShortcutRow: View {
    let shortcut: KeyboardShortcut?
    let label: LocalizedStringKey
    var alternative: LocalizedStringKey?
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OnboardingRow(icon: AnyView(Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tint).opacity(done ? 1 : 0)),
                          title: Text(label), detail: alternative.map { Text($0) }) {
                if let shortcut { Keycaps(shortcut) }
            }
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        }
        .buttonStyle(QuietButtonStyle())
        .browserAnimation(value: done)
        .accessibilityAddTraits(done ? .isSelected : [])
        .accessibilityIdentifier("onboarding.shortcut")
    }
}

/// The dots between the source's icon and Aero's, pulsing while things travel.
private struct ImportTrail: View {
    let active: Bool
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                ForEach(0..<9, id: \.self) { index in
                    let wave = active && !reduceMotion ? max(0, sin(phase * 5.5 - Double(index) * 0.55)) : 1
                    Circle().fill(.tint).opacity(active ? 0.25 + 0.75 * wave : 1)
                        .frame(width: 4, height: 4).scaleEffect(active ? 1 + 0.5 * wave : 1)
                }
            }
        }
    }
}

/// An installed browser's own icon, found from its bundle identifier.
struct BrowserIcon: View {
    let bundleIdentifier: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        } else {
            Image(systemName: "globe").resizable().scaledToFit().padding(6).foregroundStyle(.secondary)
        }
    }
}
