import BrowserCore
import SwiftUI

struct BrowserWindowView: View {
    static let windowID = "browser"

    let browser: BrowserModel
    @State private var sidebarRevealed = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .preferredColorScheme(browser.preferences.appearance.colorScheme)
    }

    private var content: some View {
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
                .browserSurface(fill: BrowserPalette(scheme: scheme).canvas,
                                border: BrowserPalette(scheme: scheme).line,
                                radius: BrowserDesign.Radius.page)
                .padding(.trailing, BrowserDesign.pageInset)
                .padding(.vertical, BrowserDesign.pageInset)
                .padding(.leading, browser.window.sidebarPinned ? 0 : BrowserDesign.pageInset)
            }
            .allowsHitTesting(browser.window.commandBar == nil)
            if !browser.window.sidebarPinned {
                Color.clear
                    .frame(width: BrowserDesign.sidebarRevealEdgeWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { if $0 { sidebarRevealed = true } }
                    .allowsHitTesting(!sidebarRevealed && browser.window.commandBar == nil)
                if sidebarRevealed {
                    SidebarView(browser: browser)
                        .frame(width: BrowserDesign.sidebarWidth)
                        .frame(maxHeight: .infinity)
                        .browserSurface(fill: BrowserPalette(scheme: scheme).sidebar,
                                        border: BrowserPalette(scheme: scheme).line,
                                        radius: BrowserDesign.Radius.floatingSidebar)
                        .floatShadow()
                        .padding(BrowserDesign.floatingInset)
                        .contentShape(Rectangle())
                        .onHover { if !$0 { sidebarRevealed = false } }
                        .allowsHitTesting(browser.window.commandBar == nil)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            if let request = browser.window.commandBar {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture { browser.window.commandBar = nil }
                    .accessibilityHidden(true)
                CommandBarView(browser: browser, request: request)
                    .id(request.id)
                    .frame(maxWidth: BrowserDesign.paletteWidth)
                    .padding(.top, 120)
                    .padding(.horizontal, 48)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .frame(minWidth: 820, minHeight: 580)
        .ignoresSafeArea(.container, edges: .top)
        .background(BrowserPalette(scheme: scheme).sidebar)
        .foregroundStyle(BrowserPalette(scheme: scheme).ink)
        .font(BrowserDesign.Typography.chrome)
        .tint(browser.profile?.color.tint ?? ProfileColor.terracotta.tint)
        .browserAnimation(value: browser.window.sidebarPinned)
        .browserAnimation(value: sidebarRevealed)
        .browserAnimation(value: browser.window.commandBar != nil)
        .browserAnimation(value: browser.window.find.isPresented)
        .downloadsDockBadge(activeCount: browser.downloads.activeCount)
        .onChange(of: browser.window.sidebarPinned) { _, _ in sidebarRevealed = false }
        .onChange(of: browser.window.commandBar != nil) { _, presented in if presented { sidebarRevealed = false } }
        .background(WindowConfiguration())
        .focusedSceneValue(\.browserModel, browser)
        .sheet(isPresented: Binding(get: { browser.window.profilesPresented }, set: { browser.window.profilesPresented = $0 })) {
            ProfilesView(browser: browser)
        }
        .alert("Something needs your attention", isPresented: Binding(get: { browser.errorMessage != nil }, set: { if !$0 { browser.errorMessage = nil } })) {
            Button("OK", role: .cancel) { browser.errorMessage = nil }
        } message: { Text(verbatim: browser.errorMessage ?? "") }
    }
}
