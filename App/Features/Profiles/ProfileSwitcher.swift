import SwiftUI

struct ProfileSwitcher: View {
    let browser: BrowserModel
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 6) {
                if let profile = browser.profile {
                    Text(verbatim: profile.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Circle().fill(profile.color.tint).frame(width: 5, height: 5)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .frame(height: BrowserDesign.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch profile")
        .accessibilityValue(browser.profile?.name ?? "")
        .accessibilityIdentifier("sidebar.profiles")
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your profiles").font(.caption).foregroundStyle(.secondary).padding(8)
                ForEach(browser.session.profiles) { profile in
                    Button {
                        browser.switchProfile(profile.id)
                        presented = false
                    } label: {
                        HStack(spacing: 10) {
                            ProfileBadge(profile: profile, size: 24)
                            Text(verbatim: profile.name).lineLimit(1)
                            Spacer()
                            if profile.id == browser.window.selectedProfileID { Image(systemName: "checkmark").font(.caption) }
                        }
                        .padding(8).contentShape(Rectangle())
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                Divider().padding(.vertical, 4)
                Button {
                    presented = false
                    browser.perform(.profiles)
                } label: {
                    Label("Manage profiles", systemImage: "person.crop.circle.badge.plus")
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(8).frame(width: 240)
        }
    }
}
