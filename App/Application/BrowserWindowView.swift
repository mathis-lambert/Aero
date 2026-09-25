import BrowserCore
import SwiftUI

struct BrowserWindowView: View {
    static let windowID = "browser"
    /// The control bar's top edge over a tab, as a share of the window height.
    private static let controlBarPosition: CGFloat = 0.28

    let browser: BrowserModel
    @State private var sidebarRevealed = false
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if browser.window.sidebarPinned {
                    SidebarView(browser: browser)
                        .frame(width: BrowserDesign.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ZStack {
                    if !browser.isReady {
                        if browser.loadFailed {
                            ContentUnavailableView("Session unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text("Your saved data has been kept unchanged."))
                        } else { ProgressView().controlSize(.small) }
                    } else if let internalPage = browser.internalPage {
                        InternalPageView(page: internalPage, browser: browser)
                    } else if let page = browser.currentPage {
                        BrowserContentView(page: page)
                            .overlay(alignment: .topTrailing) {
                                if browser.window.find.isPresented {
                                    FindBar(find: browser.window.find, page: page)
                                        .padding(BrowserDesign.floatingInset)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
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
            .allowsHitTesting(browser.window.controlBar == nil)
            if !browser.window.sidebarPinned {
                Color.clear
                    .frame(width: BrowserDesign.sidebarRevealEdgeWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { if $0 { sidebarRevealed = true } }
                    .allowsHitTesting(!sidebarRevealed && browser.window.controlBar == nil)
                if sidebarRevealed {
                    SidebarView(browser: browser)
                        .frame(width: BrowserDesign.sidebarWidth)
                        .frame(maxHeight: .infinity)
                        .browserSurface(fill: palette.sidebar, border: palette.line, radius: BrowserDesign.Radius.floatingSidebar)
                        .floatShadow()
                        .padding(BrowserDesign.floatingInset)
                        .contentShape(Rectangle())
                        .onHover { if !$0 { sidebarRevealed = false } }
                        .allowsHitTesting(browser.window.controlBar == nil)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            if let presentation = browser.window.controlBar {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture { browser.window.controlBar = nil }
                    .accessibilityHidden(true)
                GeometryReader { geometry in
                    ControlBarView(browser: browser, presentation: presentation)
                        .id(presentation.id)
                        .padding(.top, geometry.size.height * Self.controlBarPosition)
                        .frame(maxWidth: .infinity)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
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
        .onChange(of: browser.window.sidebarPinned) { _, _ in sidebarRevealed = false }
        .onChange(of: browser.window.controlBar != nil) { _, presented in if presented { sidebarRevealed = false } }
        .background(WindowConfiguration())
        .focusedSceneValue(\.browserModel, browser)
        .sheet(isPresented: Binding(get: { browser.window.profilesPresented }, set: { browser.window.profilesPresented = $0 })) {
            ProfilesView(browser: browser)
        }
        .alert("Something needs your attention", isPresented: Binding(get: { browser.errorMessage != nil }, set: { if !$0 { browser.errorMessage = nil } })) {
            Button("OK", role: .cancel) { browser.errorMessage = nil }
        } message: { Text(verbatim: browser.errorMessage ?? "") }
        .preferredColorScheme(browser.preferences.appearance.colorScheme)
    }
}
