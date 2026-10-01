import BrowserCore
import SwiftUI

struct SpacesSettingsView: View {
    let browser: BrowserModel
    let navigate: (SettingsRoute) -> Void
    @State private var dragSessionID: DragSession.ID?
    @State private var reorders = 0
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// A List, unlike a Form, reorders its rows by dragging them.
    var body: some View {
        List {
            Section {
                ForEach(browser.session.spaces) { space in row(space) }
                    .onMove { offsets, destination in
                        let previous = browser.session.spaces.map(\.id)
                        browser.reorderSpaces(from: offsets, to: destination)
                        if browser.session.spaces.map(\.id) != previous { reorders += 1 }
                    }
            } footer: {
                Text("Spaces organize tabs by context. Drag them to set their order in the sidebar.")
            }
            Section {
                Button { newSpace() } label: { Label("New space…", systemImage: "plus") }
            }
        }
        .onDragSessionUpdated { session in
            switch session.phase {
            case .initial, .active: dragSessionID = session.id
            case .ended: if dragSessionID == session.id { dragSessionID = nil }
            default: break
            }
        }
        .listStyle(.inset)
        .sensoryFeedback(.levelChange, trigger: reorders)
        .sensoryFeedback(.levelChange, trigger: dragSessionID) { _, new in new != nil }
        .disabled(browser.isChangingStructure)
    }

    private func row(_ space: BrowserSpace) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .accessibilityLabel(Text(verbatim: space.name))
                .accessibilityIdentifier("spaces.drag.\(space.name)")
            SettingsRow(title: space.name, open: { navigate(.space(space.id)) }) {
                SpaceTile(space: space)
            } subtitle: {
                Text("\(browser.session.tabs.count { $0.spaceID == space.id }) tabs")
            } trailing: {
                Label {
                    Text(verbatim: browser.profiles.first { $0.id == space.profileID }?.name ?? "")
                } icon: { Image(systemName: "person.crop.circle") }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .accessibilityIdentifier("spaces.row.\(space.name)")
        }
    }

    private func newSpace() {
        dismissWindow()
        openWindow(id: BrowserWindowView.windowID)
        browser.present(.space(nil))
    }
}
