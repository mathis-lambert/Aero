import BrowserCore
import SwiftUI

struct BrowserWindowView: View {
    static let windowID = "browser"
    /// The control bar's top edge over a tab, as a share of the window height.
    private static let controlBarPosition: CGFloat = 0.28

    let browser: BrowserModel
    @State private var sidebarRevealed = false
    @State private var resizingSidebarWidth: CGFloat?
    @State private var windowControls = WindowControls()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    /// The prompt shown in this window; an extension request asked from Settings shows there.
    private var prompt: WindowPrompt? { browser.window.prompt.flatMap { $0.isInSettings ? nil : $0 } }
    /// The control bar or a prompt covers the window, which then takes no clicks.
    private var isOverlaid: Bool { browser.window.controlBar != nil || prompt != nil }

    /// The size the browser opens at without a saved frame, and grows to after the first launch's onboarding.
    static func preferredSize(on screen: CGSize) -> CGSize {
        CGSize(width: min(1440, screen.width * 0.9), height: min(920, screen.height * 0.9))
    }

    /// The first launch's onboarding replaces the browser, in a compact window; a later import covers it instead.
    private var showsFirstLaunch: Bool { browser.isReady && browser.onboarding?.mode == .firstLaunch }

    var body: some View {
        let compact = showsFirstLaunch ? OnboardingWindow.size : nil
        content
            .browserAnimation(value: browser.onboarding == nil)
            // SwiftUI owns the window's limits through the scene's `contentSize` resizability; they change at once.
            .frame(minWidth: compact?.width ?? 820, maxWidth: compact?.width ?? .infinity,
                   minHeight: compact?.height ?? 580, maxHeight: compact?.height ?? .infinity)
            .animation(nil, value: compact)
            .onChange(of: showsFirstLaunch) { _, shows in
                guard let window = WindowConfiguration.mainWindow else { return }
                // After SwiftUI has applied the new limits: resizing inside its update re-enters it.
                Task { [weak window, reduceMotion] in
                    guard let window, window.isVisible, shows == showsFirstLaunch else { return }
                    OnboardingWindow.resize(window, forOnboarding: shows, animated: !reduceMotion)
                }
            }
            .environment(\.windowControls, windowControls)
            .background(WindowConfiguration(controls: windowControls))
            // Menus reach the browser even while the onboarding covers it.
            .focusedSceneValue(\.browserModel, browser)
    }

    @ViewBuilder private var content: some View {
        switch browser.startup {
        case .loading:
            // The window opens after startup; this shows only if it is opened sooner, from the Dock or a menu.
            Color.clear
        case .failed(let failure):
            StorageRecoveryView(browser: browser, failure: failure)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    NativeWindowControls().frame(width: BrowserDesign.windowControlsWidth, height: 44)
                }
                .prompt(prompt, onCancel: browser.dismissPrompt) { WindowPromptView(browser: browser, prompt: $0) }
        case .ready:
            if let onboarding = browser.onboarding, onboarding.mode == .firstLaunch {
                OnboardingView(browser: browser, onboarding: onboarding)
                    .transition(.opacity)
            } else {
                browserContent
                    // Nothing behind an import keeps focus or takes keys.
                    .disabled(browser.onboarding != nil)
                    .overlay {
                        if let onboarding = browser.onboarding {
                            OnboardingView(browser: browser, onboarding: onboarding)
                                .transition(.opacity)
                        }
                    }
            }
        }
    }

    private var browserContent: some View {
        GeometryReader { geometry in
            let maximumWidth = max(BrowserDesign.sidebarWidth, geometry.size.width / 3)
            let sidebarWidth = min(resizingSidebarWidth ?? browser.preferences.sidebarWidth, maximumWidth)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if browser.window.sidebarPinned {
                        SidebarView(browser: browser)
                            .frame(width: sidebarWidth)
                            .overlay(alignment: .trailing) {
                                resizeHandle(width: sidebarWidth, maximum: maximumWidth)
                            }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    Group {
                        // A tab alone is a layout of one pane, so a pane coming beside it, or going, moves the same page.
                        if let layout = browser.paneLayout {
                            SplitPageView(browser: browser, layout: layout)
                                .id(browser.window.paneGroup)
                        } else {
                            NewTabView(browser: browser)
                                .id([browser.window.selectedSpaceID, browser.profile?.id])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .browserSurface(fill: palette.canvas, border: palette.line, radius: BrowserDesign.Radius.page)
                                .background {
                                    RoundedRectangle(cornerRadius: BrowserDesign.Radius.page).fill(palette.canvas).pageShadow(palette.scheme)
                                }
                        }
                    }
                    .splitDropZones(browser)
                    .pageCornerActions(browser)
                    // The whole page, frame and shadow included, or the split's panes, step back in the window under a
                    // link's preview.
                    .peekPresentation(browser)
                    .padding(.trailing, BrowserDesign.pageInset)
                    .padding(.vertical, BrowserDesign.pageInset)
                    .padding(.leading, browser.window.sidebarPinned ? 0 : BrowserDesign.pageInset)
                }
                .allowsHitTesting(!isOverlaid)
                if !browser.window.sidebarPinned {
                    Color.clear
                        .frame(width: BrowserDesign.sidebarRevealEdgeWidth)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onHover { if $0 { sidebarRevealed = true } }
                        .allowsHitTesting(!sidebarRevealed && !isOverlaid)
                    if sidebarRevealed || browser.window.holdsSidebarOpen {
                        SidebarView(browser: browser)
                            .frame(width: sidebarWidth)
                            .frame(maxHeight: .infinity)
                            .browserGlass(.sidebar, radius: BrowserDesign.Radius.floatingSidebar)
                            .overlay(alignment: .trailing) {
                                resizeHandle(width: sidebarWidth, maximum: maximumWidth)
                            }
                            .floatShadow()
                            .padding(BrowserDesign.floatingInset)
                            .contentShape(Rectangle())
                            .onHover { if !$0 && resizingSidebarWidth == nil { sidebarRevealed = false } }
                            .allowsHitTesting(!isOverlaid)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                if browser.window.controlBar != nil {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { browser.window.controlBar = nil }
                        .accessibilityHidden(true)
                }
                if let presentation = browser.window.controlBar {
                    ControlBarView(browser: browser, presentation: presentation)
                        .id(presentation.id)
                        .padding(.top, geometry.size.height * Self.controlBarPosition)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .modifier(WindowBackdrop(accent: browser.accent))
        .foregroundStyle(palette.ink)
        .font(BrowserDesign.Typography.chrome)
        .tint(browser.accent.tint)
        .browserAnimation(value: browser.window.sidebarPinned)
        .browserAnimation(value: sidebarRevealed)
        .browserAnimation(value: browser.window.controlBar != nil)
        .browserAnimation(value: browser.window.find.isPresented)
        .downloadFlights(browser.downloads)
        .onChange(of: browser.window.settingsRequest) { openWindow(id: SettingsView.windowID) }
        .prompt(prompt, onCancel: browser.dismissPrompt) { WindowPromptView(browser: browser, prompt: $0) }
        .onChange(of: browser.window.sidebarPinned) { _, _ in
            sidebarRevealed = false
            resizingSidebarWidth = nil
        }
        .onChange(of: isOverlaid) { _, overlaid in if overlaid { sidebarRevealed = false } }
        .onChange(of: browser.window.selectedTabID) { _, _ in
            browser.window.zoomFeedback = nil
            browser.window.siteSettingsPresented = false
            browser.window.controlCenterPresented = false
            browser.window.portrait = nil
            browser.window.tabSelection.clear()
        }
        .onExitCommand {
            // Escape reaches here only after focused controls have had their dismissal opportunity.
            if browser.window.peek != nil {
                browser.dismissPeek()
            } else if !browser.window.tabSelection.isEmpty {
                browser.window.tabSelection.clear()
            } else if browser.window.controlBar == nil, browser.window.prompt == nil,
               !browser.window.find.isPresented, browser.window.renaming == nil,
               !browser.window.holdsSidebarOpen, browser.isEnabled(.stopLoading) {
                browser.perform(.stopLoading)
            }
        }
    }

    private func resizeHandle(width: CGFloat, maximum: CGFloat) -> some View {
        SidebarResizeHandle(width: width, maximum: maximum) { width in
            resizingSidebarWidth = width
        } onEnd: { width in
            resizingSidebarWidth = nil
            if let width {
                browser.preferences.sidebarWidth = width
            } else {
                browser.window.sidebarPinned = false
                sidebarRevealed = false
            }
        }
    }
}

/// The card for each of the window's prompts. See docs/DESIGN.md › Prompts.
struct WindowPromptView: View {
    let browser: BrowserModel
    let prompt: WindowPrompt

    var body: some View {
        switch prompt {
        case .quit: QuitPrompt(browser: browser)
        case .space(let target): SpacePrompt(browser: browser, profileID: target)
        case .removeSpace(let id, _): SpaceRemovalPrompt(browser: browser, spaceID: id)
        case .moveTab(let move): TabMovePrompt(browser: browser, presentation: move)
        case .transferTabs(let transfer): TabTransferPrompt(browser: browser, transfer: transfer)
        case .profile(_, let onCreated): ProfilePrompt(browser: browser, onCreated: onCreated)
        case .clearHistory(let clear): ClearHistoryPrompt(browser: browser, clear: clear)
        case .extensionRequest(let request): ExtensionRequestPrompt(browser: browser, request: request)
        case .applicationLink(let link): ApplicationLinkPrompt(browser: browser, link: link)
        case .confirmation(let confirmation): ConfirmationPrompt(browser: browser, confirmation: confirmation)
        case .pageDialog(let request): PageDialogCard(dialog: request.dialog) { browser.answer(request, $0) }
        case .portrait(let studio): PortraitStudioView(browser: browser, studio: studio)
        case .error(let message):
            Prompt(title: Text("Something needs your attention"), message: Text(verbatim: message)) {
                PromptConfirmButton(title: "OK") { browser.dismissPrompt() }
                    .accessibilityIdentifier("error.dismiss")
            }
        }
    }
}
