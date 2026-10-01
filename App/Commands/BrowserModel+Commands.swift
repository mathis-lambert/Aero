import BrowserCore
import Foundation

extension BrowserModel {
    /// Nothing runs behind a prompt.
    func isEnabled(_ command: BrowserCommand) -> Bool {
        if command == .checkForUpdates { return updater.canCheck && window.prompt == nil && onboarding == nil && !isChangingStructure }
        guard isReady, !isChangingStructure, window.prompt == nil else { return false }
        // The onboarding covers the browser: Back goes to its previous step, only the shortcuts it teaches reach it,
        // and nothing acts behind it.
        if let onboarding {
            if command == .back { return onboarding.canGoBack }
            return onboarding.step == .gettingAround && OnboardingModel.taughtCommands.contains(command)
        }
        switch command {
        case .back: return currentPage?.canGoBack == true
        case .forward: return currentPage?.canGoForward == true
        case .reload, .reloadFromOrigin, .zoomIn, .zoomOut, .resetZoom, .printPage, .savePage, .exportAsPDF: return currentPage != nil
        case .stopLoading: return currentPage?.isLoading == true
        case .duplicateTab, .renameTab, .toggleFavorite, .newGroup: return selectedTab != nil
        case .moveToSpace: return selectedTab != nil && session.spaces.count > 1
        case .moveToGroup: return selectedTab != nil && space?.groups.isEmpty == false
        case .closeOtherTabs, .closeFollowingTabs: return selectedTab != nil && orderedTabs.count > 1
        case .nextTab, .previousTab, .recentTab, .previousRecentTab: return !tabs.isEmpty
        case .tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8, .lastTab:
            return command.tabIndex.map { orderedTabs.indices.contains($0) } ?? !orderedTabs.isEmpty
        case .nextSpace, .previousSpace: return session.spaces.count > 1
        case .closeTab: return selectedTab != nil
        case .findInPage, .findNext, .findPrevious: return currentPage != nil
        case .reopenTab: return canReopen
        case .copyLink, .controlCenter, .clearCookies, .clearCache, .siteSettings: return currentSite != nil
        default: return true
        }
    }

    func perform(_ command: BrowserCommand) {
        guard isEnabled(command) else { return }
        if let onboarding {
            if command == .back { onboarding.back(); return }
            onboarding.tried(command)
            // Switching spaces is real: the preview shows the browser's own spaces.
            guard command == .nextSpace || command == .previousSpace, session.spaces.count > 1 else { return }
        }
        switch command {
        case .checkForUpdates: updater.check()
        case .newTab:
            window.controlBar = nil
            if let page = profile.flatMap({ extensionNewTabPage(inProfile: $0.id) }) { open(page) }
            else {
                selectTab(nil)
                window.inputFocusRequest = UUID()
            }
        // The New Tab page's own bar takes both shortcuts, so a second bar never opens over it.
        case .openLocation:
            if let selectedTab { window.controlBar = ControlBarPresentation(target: .currentTab, initialText: selectedTab.url.absoluteString) }
            else { window.inputFocusRequest = UUID() }
        case .commandPalette:
            if selectedTab != nil { window.controlBar = ControlBarPresentation(target: .newTab, initialText: "") }
            else { window.inputFocusRequest = UUID() }
        case .zoomIn, .zoomOut, .resetZoom:
            if let page = currentPage, let tabID = window.selectedTabID {
                if command == .resetZoom { page.resetZoom() }
                else { page.changeZoom(increasing: command == .zoomIn) }
                window.zoomFeedback = PageZoomFeedback(tabID: tabID, scale: page.zoom)
                if let tab = selectedTab { extensionsDidChange(tab, .zoomFactor) }
            }
        case .reloadFromOrigin: currentPage?.reloadFromOrigin()
        case .stopLoading: currentPage?.stop()
        case .printPage: currentPage?.printPage()
        case .showDownloads: window.downloadsPresented.toggle()
        case .nextTab, .previousTab: selectAdjacentTab(backwards: command == .previousTab)
        case .recentTab, .previousRecentTab:
            cycleTab(backwards: command == .previousRecentTab)
            commitTabCycle()
        case .tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8, .lastTab:
            let ordered = orderedTabs
            if let index = command.tabIndex, ordered.indices.contains(index) { selectTab(ordered[index].id) }
            else if command == .lastTab { selectTab(ordered.last?.id) }
        case .toggleFavorite:
            if let tab = selectedTab {
                if tab.isFavorite { removeFavorite(tab.id) }
                else { moveTab(tab.id, to: .grid, before: nil) }
            }
        case .duplicateTab: if let id = window.selectedTabID { duplicateTab(id) }
        case .renameTab: if let id = window.selectedTabID { window.renaming = .tab(id) }
        case .newGroup: if let id = window.selectedTabID { newGroup(with: id) }
        case .closeOtherTabs, .closeFollowingTabs:
            let ordered = orderedTabs
            if let index = ordered.firstIndex(where: { $0.id == window.selectedTabID }) {
                let closing = command == .closeOtherTabs ? ordered.filter { $0.id != window.selectedTabID } : Array(ordered.dropFirst(index + 1))
                for tab in closing { closeTab(tab.id) }
            }
        case .moveToGroup, .moveToSpace:
            if let id = window.selectedTabID { present(.moveTab(.init(tabID: id, target: command == .moveToSpace ? .space : .group))) }
        case .nextSpace, .previousSpace:
            let spaces = session.spaces
            if let index = spaces.firstIndex(where: { $0.id == window.selectedSpaceID }) {
                switchSpace(spaces[(index + (command == .nextSpace ? 1 : spaces.count - 1)) % spaces.count].id)
            }
        case .back: currentPage?.goBack()
        case .forward: currentPage?.goForward()
        case .reload: currentPage?.reload()
        case .closeTab: if let id = window.selectedTabID { closeTab(id) }
        case .reopenTab: reopenTab()
        case .toggleSidebar: window.sidebarPinned.toggle()
        case .profiles: showSettings(.section(.profiles))
        case .passwords: showSettings(.section(.passwords))
        case .importBrowserData: beginImport()
        case .openFile: chooseFileToOpen()
        case .savePage: if let page = currentPage { savePage(page, as: .webArchive) }
        case .exportAsPDF: if let page = currentPage { savePage(page, as: .pdf) }
        case .newProfile: present(.profile())
        case .newSpace: present(.space(nil))
        case .showHistory: show(.history)
        case .findInPage, .findNext, .findPrevious: find(command)
        case .copyLink: copyLink()
        case .controlCenter: window.controlCenterPresented = true
        case .clearCookies: Task { await clearSiteData(.cookies) }
        case .clearCache: Task { await clearSiteData(.cache) }
        case .siteSettings: window.siteSettingsPresented = true
        }
    }

    /// Next and previous open the bar first when there is nothing to search for yet.
    private func find(_ command: BrowserCommand) {
        guard let page = currentPage else { return }
        let find = window.find
        Task {
            if command == .findInPage || find.query.isEmpty { await find.present(on: page) }
            else { await find.search(on: page, backwards: command == .findPrevious) }
        }
    }

    var shortcuts: ShortcutPreferences { preferences.shortcuts }

    /// Includes collapsed groups; hiding a group does not renumber the browser's tabs.
    var orderedTabs: [BrowserTab] {
        guard let space else { return [] }
        let layout = SidebarTabs(session: session, space: space, drop: nil)
        return layout.grid + layout.groups.flatMap(\.tabs) + layout.loose + layout.open
    }

    func selectAdjacentTab(backwards: Bool) {
        let ordered = orderedTabs
        guard !ordered.isEmpty else { return }
        let index = ordered.firstIndex { $0.id == window.selectedTabID }
        let next = index.map { ($0 + (backwards ? ordered.count - 1 : 1)) % ordered.count }
            ?? (backwards ? ordered.count - 1 : 0)
        selectTab(ordered[next].id)
    }
}
