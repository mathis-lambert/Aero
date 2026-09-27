import SwiftUI

struct TabMovePresentation: Identifiable {
    let tabID: UUID
    let isProfile: Bool
    var id: UUID { tabID }
}

struct TabDestinationSheet: View {
    let browser: BrowserModel
    let destination: TabMovePresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(destination.isProfile ? "Move tab to profile…" : "Move tab to group…").font(.headline)
            if destination.isProfile {
                ForEach(browser.session.profiles.filter { $0.id != browser.session.tabs.first(where: { $0.id == destination.tabID }).flatMap(browser.profileID(of:)) }) { profile in
                    Button(profile.name) {
                        browser.moveTab(destination.tabID, toProfile: profile.id)
                        dismiss()
                    }
                }
            } else {
                ForEach(browser.space?.groups ?? []) { group in
                    Button(group.name) {
                        browser.moveTab(destination.tabID, to: .list(group: group.id), before: nil)
                        dismiss()
                    }
                }
                if case .list(group: .some) = browser.session.tabs.first(where: { $0.id == destination.tabID })?.place {
                    Button("Out of Group") {
                        browser.moveTab(destination.tabID, to: .list(group: nil), before: nil)
                        dismiss()
                    }
                }
            }
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(minWidth: 300)
    }
}
