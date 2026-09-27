import AppKit
import BrowserCore
import SwiftUI

struct SpacesSettingsView: View {
    let browser: BrowserModel
    let navigate: (SettingsRoute) -> Void
    @State private var dragSessionID: DragSession.ID?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.palette) private var palette

    /// The page is one List, for native drag reordering from each row's leading handle. Nothing is
    /// stacked beside it: a sibling or inset lets the List outgrow the fixed-size window.
    var body: some View {
        List {
            // A static first row; only the spaces below it reorder.
            SettingsListIntro(text: "Spaces organize tabs by context. Drag them to set their order in the sidebar.") {
                Button { newSpace() } label: { Label("New space…", systemImage: "plus") }
            }
            .padding(.top, 20)
            .padding(.bottom, 10)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            ForEach(browser.session.spaces) { space in
                row(space)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
            }
            .onMove { offsets, destination in
                let previous = browser.session.spaces.map(\.id)
                browser.reorderSpaces(from: offsets, to: destination)
                if browser.session.spaces.map(\.id) != previous {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            }
        }
        .onDragSessionUpdated { session in
            switch session.phase {
            case .initial, .active:
                guard dragSessionID != session.id else { return }
                dragSessionID = session.id
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            case .ended:
                if dragSessionID == session.id { dragSessionID = nil }
            default: break
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: BrowserDesign.listWidth)
        .frame(maxWidth: .infinity)
        .disabled(browser.isChangingStructure)
    }

    private func row(_ space: BrowserSpace) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(BrowserDesign.Typography.chrome)
                .foregroundStyle(palette.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .accessibilityLabel(Text(verbatim: space.name))
                .accessibilityIdentifier("spaces.drag.\(space.name)")
            Button { navigate(.space(space.id)) } label: {
                SettingsRow(title: space.name) {
                    SpaceTile(space: space)
                } subtitle: {
                    Text("\(browser.session.tabs.count { $0.spaceID == space.id }) tabs")
                } trailing: {
                    Label {
                        Text(verbatim: browser.profiles.first { $0.id == space.profileID }?.name ?? "")
                    } icon: { Image(systemName: "person.crop.circle") }
                    .font(BrowserDesign.Typography.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                }
            }
            .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
            .accessibilityIdentifier("spaces.row.\(space.name)")
        }
    }

    private func newSpace() {
        dismissWindow(id: SettingsView.windowID)
        openWindow(id: BrowserWindowView.windowID)
        browser.present(.space(nil))
    }
}
