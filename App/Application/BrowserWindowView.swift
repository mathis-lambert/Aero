import BrowserCore
import SwiftUI

struct BrowserWindowView: View {
    static let windowID = "browser"
    /// The control bar's top edge over a tab, as a share of the window height.
    private static let controlBarPosition: CGFloat = 0.28

    let browser: BrowserModel
    @State private var sidebarRevealed = false
    @State private var resizingSidebarWidth: CGFloat?
    @Environment(\.palette) private var palette

    /// The prompt shown in this window; an extension request asked from Settings shows there.
    private var prompt: WindowPrompt? { browser.window.prompt.flatMap { $0.isInSettings ? nil : $0 } }
    /// The control bar or a prompt covers the window, which then takes no clicks.
    private var isOverlaid: Bool { browser.window.controlBar != nil || prompt != nil }

    var body: some View {
        GeometryReader { geometry in
            let maximumWidth = max(BrowserDesign.sidebarWidth, geometry.size.width / 3)
            let sidebarWidth = min(resizingSidebarWidth ?? browser.preferences.sidebarWidth, maximumWidth)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if browser.window.sidebarPinned {
                        SidebarView(browser: browser)
                            .disabled(!browser.isReady)
                            .frame(width: sidebarWidth)
                            .overlay(alignment: .trailing) {
                                resizeHandle(width: sidebarWidth, maximum: maximumWidth)
                            }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    ZStack {
                        if !browser.isReady {
                            if browser.loadFailed {
                                StorageRecoveryView(browser: browser)
                            } else { ProgressView().controlSize(.small) }
                        } else if let internalPage = browser.internalPage {
                            InternalPageView(page: internalPage, browser: browser)
                                .id(browser.window.selectedProfileID)
                        } else if let page = browser.currentPage {
                            BrowserContentView(page: page)
                                .overlay(alignment: .topTrailing) {
                                    VStack(alignment: .trailing, spacing: 8) {
                                        if browser.window.find.isPresented {
                                            FindBar(find: browser.window.find, page: page, shortcuts: browser.shortcuts)
                                                .transition(.move(edge: .top).combined(with: .opacity))
                                        }
                                        if let feedback = browser.window.zoomFeedback, feedback.tabID == browser.window.selectedTabID {
                                            PageZoomIndicator(feedback: feedback) {
                                                if browser.window.zoomFeedback?.id == feedback.id { browser.window.zoomFeedback = nil }
                                            }
                                            .transition(.asymmetric(
                                                insertion: .scale(scale: 0.88, anchor: .topTrailing).combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                        }
                                    }
                                    .padding(BrowserDesign.floatingInset)
                                    .browserAnimation(value: browser.window.zoomFeedback != nil)
                                }
                        } else {
                            NewTabView(browser: browser)
                                .id(browser.window.selectedProfileID)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .browserSurface(fill: palette.canvas, border: palette.line, radius: BrowserDesign.Radius.page)
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
                            .disabled(!browser.isReady)
                            .frame(width: sidebarWidth)
                            .frame(maxHeight: .infinity)
                            .browserSurface(fill: palette.sidebar, border: palette.line, radius: BrowserDesign.Radius.floatingSidebar)
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
        .frame(minWidth: 820, minHeight: 580)
        .ignoresSafeArea(.container, edges: .top)
        .background(palette.sidebar)
        .foregroundStyle(palette.ink)
        .font(BrowserDesign.Typography.chrome)
        .tint(browser.accent.tint)
        .browserAnimation(value: browser.window.sidebarPinned)
        .browserAnimation(value: sidebarRevealed)
        .browserAnimation(value: browser.window.controlBar != nil)
        .browserAnimation(value: browser.window.find.isPresented)
        .downloadsDockBadge(activeCount: browser.downloads.activeCount)
        .downloadFlights(browser.downloads)
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
        }
        .sheet(item: Bindable(browser.window).tabDestination) { destination in
            TabDestinationSheet(browser: browser, destination: destination)
        }
        .onExitCommand {
            // Escape reaches here only after focused controls have had their dismissal opportunity.
            if browser.window.controlBar == nil, browser.window.prompt == nil,
               !browser.window.find.isPresented, browser.window.renaming == nil,
               !browser.window.holdsSidebarOpen, browser.isEnabled(.stopLoading) {
                browser.perform(.stopLoading)
            }
        }
        .background(WindowConfiguration())
        .focusedSceneValue(\.browserModel, browser)
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
        case .profile(let target): ProfilePrompt(browser: browser, target: target)
        case .clearHistory(let clear): ClearHistoryPrompt(browser: browser, clear: clear)
        case .extensionRequest(let request): ExtensionRequestPrompt(browser: browser, request: request)
        case .error(let message):
            Prompt(title: Text("Something needs your attention"), message: Text(verbatim: message)) {
                PromptConfirmButton(title: "OK") { browser.dismissPrompt() }
                    .accessibilityIdentifier("error.dismiss")
            }
        }
    }
}
