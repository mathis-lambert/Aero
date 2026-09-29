import BrowserCore
import BrowserStorage
import SwiftUI

/// The first launch in place of the browser, or an import over it (docs/ONBOARDING.md). A plate on the leading side carries
/// the words; the stage on the trailing side shows what each step does, over the wind.
struct OnboardingView: View {
    static let plateWidth: CGFloat = 472

    let browser: BrowserModel
    let onboarding: OnboardingModel
    @State private var ripple: WindRipple?
    @State private var activity = 0
    @FocusState private var isFocused: Bool
    @Environment(\.brand) private var brand
    @Environment(\.browserReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            let layout = OnboardingLayout(size: proxy.size, plateWidth: min(Self.plateWidth, proxy.size.width * 0.46))
            let welcome = onboarding.step == .welcome
            ZStack(alignment: .topLeading) {
                // The dots sit behind text and previews: plain paper when transparency or contrast asks for it.
                if !reduceTransparency, contrast != .increased {
                    OnboardingWind(shape: windShape(in: layout), ink: windInk, paper: brand.paper,
                                   fade: isBrandMoment ? 0 : 0.5, back: isBrandMoment ? 0.22 : 0.42,
                                   gust: onboarding.step.index, gustsForward: onboarding.movesForward, ripple: ripple,
                                   activity: activity + onboarding.windEvent)
                }
                OnboardingStage(browser: browser, onboarding: onboarding, layout: layout)
                    .frame(width: layout.stageWidth, height: proxy.size.height)
                    .offset(x: layout.plateWidth)
                // On the welcome, the plate is a card set on the wind; then it becomes the leading column.
                plate
                    .frame(width: welcome ? layout.plateWidth - 20 : layout.plateWidth,
                           height: welcome ? proxy.size.height - 76 : proxy.size.height)
                    .background(brand.paper, in: RoundedRectangle(cornerRadius: welcome ? BrowserDesign.Radius.card : 0))
                    .overlay {
                        if welcome { RoundedRectangle(cornerRadius: BrowserDesign.Radius.card).strokeBorder(brand.line) }
                    }
                    .overlay(alignment: .trailing) { if !welcome { Rectangle().fill(brand.line).frame(width: 1) } }
                    .offset(x: welcome ? 20 : 0, y: welcome ? 56 : 0)
                    .animation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.12), value: welcome)
                FlyingFavicons(onboarding: onboarding, layout: layout)
            }
            .coordinateSpace(.named(OnboardingView.space))
        }
        .ignoresSafeArea()
        .background(brand.paper)
        .foregroundStyle(brand.ink)
        .overlay(alignment: .top) {
            // The window has no titlebar: its controls and a strip to drag it by.
            HStack(spacing: 0) {
                // Given back when the onboarding ends: SwiftUI may keep this view a while longer.
                NativeWindowControls(isActive: !onboarding.hasEnded).frame(width: BrowserDesign.windowControlsWidth)
                Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
            }
            .frame(height: 44)
            .ignoresSafeArea()
        }
        // Return presses the default button, Command-Left Bracket invokes Back, and arrows choose a browser.
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
            guard onboarding.step == .source else { return .ignored }
            onboarding.selectNeighbor(press.key == .downArrow ? 1 : -1)
            return .handled
        }
        // A container keeps its children's identifiers; without it, this one would replace them all.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
    }

    nonisolated static let space = "onboarding"

    private var isBrandMoment: Bool { [.welcome, .ready].contains(onboarding.step) }

    private var windInk: Color {
        isBrandMoment ? brand.blue : brand.graphite
    }

    // MARK: - Plate

    private var plate: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
            OnboardingStepView(browser: browser, onboarding: onboarding, ripple: $ripple)
                .id(onboarding.step)
                // The old words leave quickly so the two steps never read on top of each other.
                .transition(.asymmetric(insertion: .offset(x: onboarding.movesForward ? 28 : -28).combined(with: .opacity).animation(.spring(duration: 0.5, bounce: 0.12).delay(0.08)),
                                        removal: .offset(x: onboarding.movesForward ? -16 : 16).combined(with: .opacity).animation(.easeIn(duration: 0.14))))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        // The welcome card sits below the window controls; the column clears them itself.
        .padding(.top, onboarding.step == .welcome ? 28 : 60)
        .padding(.horizontal, 48)
        .padding(.bottom, 28)
        .browserAnimation(value: onboarding.step)
    }

    /// The steps so far, and leaving the whole onboarding as a quiet link across from them: a way out, never
    /// mistaken for the step's own answer.
    private var progress: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                ForEach(onboarding.mode == .firstLaunch ? Array(OnboardingStep.allCases.dropFirst()) : onboarding.steps, id: \.self) { step in
                    Capsule().fill(step.index <= onboarding.step.index ? AnyShapeStyle(.tint) : AnyShapeStyle(brand.line)).frame(height: 2)
                }
            }
            .opacity(onboarding.step == .welcome ? 0 : 1)
            .accessibilityHidden(true)
            // The default browser step says Not now itself; the last step has nothing left to skip.
            if onboarding.step != .ready, onboarding.step != .defaultBrowser {
                Button(onboarding.mode == .importOnly ? "Cancel" : "Skip setup") { onboarding.finish() }
                    .buttonStyle(QuietLinkStyle())
                    .keyboardShortcut(onboarding.mode == .importOnly ? .cancelAction : nil)
                    .disabled(onboarding.isImporting)
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
        .frame(height: 20)
        .padding(.bottom, 14)
        .transaction { $0.animation = nil }
    }

    /// The same on every step: the wordmark, then the quiet actions, and the one blue action at the bottom trailing
    /// corner, where Return goes. It swaps without motion, so buttons never slide over each other between steps. The
    /// wordmark keeps its size; when a long translation leaves no room for it, it gives way to the actions whole.
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                Text(verbatim: "Aero").font(BrandType.title(26)).fixedSize().accessibilityHidden(true)
                Spacer(minLength: 12)
                footerActions
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                footerActions
            }
        }
        .transaction { $0.animation = nil }
    }

    private var footerActions: some View {
        let step = onboarding.step
        let asksDefault = step == .defaultBrowser && !onboarding.isDefaultBrowser
        return HStack(spacing: 8) {
            if asksDefault {
                Button("Not now") { onboarding.next() }
                    .buttonStyle(PanelButtonStyle())
                    .accessibilityIdentifier("onboarding.notNow")
            }
            if step != .welcome, step != onboarding.steps.first {
                // A chevron, so the actions keep their room at any translation's length; ⌘[ goes back too.
                Button { onboarding.back() } label: {
                    Image(systemName: "chevron.left").font(BrowserDesign.Typography.chrome.weight(.semibold))
                }
                .buttonStyle(PanelButtonStyle())
                .disabled(onboarding.isImporting)
                .tooltip(Text("Back"), shortcut: KeyboardShortcut("[", modifiers: .command))
                .accessibilityLabel(Text("Back"))
                .accessibilityIdentifier("onboarding.back")
            }
            Button(action: primaryAction) {
                HStack(spacing: 8) {
                    Text(primaryTitle)
                    ReturnCap()
                }
            }
            .buttonStyle(PanelButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
            .disabled(!onboarding.canContinue)
            .accessibilityIdentifier(step == .welcome ? "onboarding.start" : asksDefault ? "onboarding.makeDefault" : "onboarding.continue")
        }
        .fixedSize()
    }

    private var primaryTitle: LocalizedStringKey {
        switch onboarding.step {
        case .welcome: "Get started"
        case .defaultBrowser where !onboarding.isDefaultBrowser: "Set as default"
        case .ready: "Start browsing"
        default: onboarding.isLastStep ? "Done" : "Continue"
        }
    }

    private func primaryAction() {
        switch onboarding.step {
        case .ready: onboarding.finish()
        case .defaultBrowser where !onboarding.isDefaultBrowser: Task { await onboarding.makeDefaultBrowser() }
        default: onboarding.next()
        }
        activity += 1
    }

    // MARK: - Wind

    /// Each step writes one shape where the stage leaves room for it.
    private func windShape(in layout: OnboardingLayout) -> WindShape {
        let top = layout.height * 0.118
        let width = layout.stageWidth - 68
        func word(_ text: String, y: CGFloat, size: CGFloat, system: Bool = false) -> WindShape.Word {
            WindShape.Word(text: text, center: CGPoint(x: layout.stageCenterX, y: y), size: size, maxWidth: width, system: system)
        }
        let sourceName = onboarding.source.map(Self.shortName) ?? "Aero"
        switch onboarding.step {
        case .welcome:
            let side = min(layout.stageWidth - 40, layout.height * 0.9)
            return WindShape(feather: CGRect(x: layout.stageCenterX - side / 2, y: layout.height * 0.5 - side / 2, width: side, height: side))
        case .source: return WindShape(words: [word(sourceName, y: layout.height * 0.16, size: layout.height * 0.28)])
        case .choice: return WindShape(words: [word(sourceName, y: layout.height * 0.147, size: layout.height * 0.22),
                                               word("Aero", y: layout.height * 0.84, size: layout.height * 0.2)])
        case .importing:
            // Halfway through, the other browser's name breaks up and gathers into Aero's.
            let halfway = (onboarding.outcome?.favorites ?? 0) > 0 || onboarding.outcome.map { !onboarding.isImporting && $0 != ImportOutcome() } == true
            return WindShape(words: [word(halfway ? "Aero" : sourceName, y: top, size: layout.height * 0.19)])
        case .gettingAround: return WindShape(words: [word(onboarding.lastShortcutSymbol, y: top, size: layout.height * 0.18, system: true)])
        case .defaultBrowser: return WindShape(ringsAround: CGPoint(x: layout.stageCenterX, y: layout.height * 0.465))
        case .ready: return WindShape(crescent: true)
        }
    }

    static func shortName(_ source: ImportSource) -> String {
        source.name == "Google Chrome" ? "Chrome" : source.name == "Microsoft Edge" ? "Edge" : source.name
    }
}

struct OnboardingLayout: Equatable {
    let size: CGSize
    let plateWidth: CGFloat
    var height: CGFloat { size.height }
    var stageWidth: CGFloat { max(0, size.width - plateWidth) }
    /// The stage's center in the whole view, where shapes are written.
    var stageCenterX: CGFloat { plateWidth + stageWidth / 2 }

    /// Where a step's picture goes on the stage, in the stage's coordinates: below or between the words the wind
    /// writes for it (`OnboardingView.windShape`), with a margin on every side.
    func stageRegion(for step: OnboardingStep) -> CGRect {
        let (top, bottom): (CGFloat, CGFloat) = switch step {
        case .welcome: (0, 1)
        case .source: (0.32, 0.96)
        case .choice: (0.25, 0.75)
        case .importing, .gettingAround: (0.24, 0.95)
        case .defaultBrowser: (0.16, 0.84)
        case .ready: (0.08, 0.8)
        }
        let margin: CGFloat = 36
        return CGRect(x: margin, y: height * top, width: max(0, stageWidth - 2 * margin), height: max(0, height * (bottom - top)))
    }

    /// Where the browser preview's favorites are, in the whole view: flights land there. The preview is centered in
    /// its region at the scale that fits it (`StageFit`).
    func previewFavorites(for step: OnboardingStep) -> CGRect {
        let region = stageRegion(for: step).offsetBy(dx: plateWidth, dy: 0)
        let size = OnboardingBrowserTwin.size
        let scale = min(1, region.width / size.width, region.height / size.height)
        let origin = CGPoint(x: region.midX - size.width * scale / 2, y: region.midY - size.height * scale / 2)
        let list = OnboardingBrowserTwin.favoritesArea
        return CGRect(x: origin.x + list.minX * scale, y: origin.y + list.minY * scale, width: list.width * scale, height: list.height * scale)
    }
}

// MARK: - Controls

/// The Return key on the primary button.
struct ReturnCap: View {
    var body: some View {
        Text(verbatim: "↵")
            .font(BrowserDesign.Typography.keycap)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.xs))
            .accessibilityHidden(true)
    }
}

/// The first launch's window: compact while the onboarding shows, then grown to the browser's size. SwiftUI owns the
/// limits (`BrowserWindowView`); this only moves the window once they changed. See docs/ONBOARDING.md › Presentation.
enum OnboardingWindow {
    static let size = CGSize(width: 1040, height: 660)

    @MainActor static func resize(_ window: NSWindow, forOnboarding onboarding: Bool) {
        guard let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = onboarding ? window.frame.size : window.frameRect(forContentRect: NSRect(origin: .zero, size: BrowserWindowView.preferredSize(on: screen.size))).size
        let target = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        guard !onboarding, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { window.setFrame(target, display: true); return }
        // Grown from the onboarding's center, through the animator: `setFrame(_:display:animate:)` spins the run loop.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(target, display: true)
        }
    }
}
