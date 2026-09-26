import BrowserCore
import SwiftUI

struct PerformanceSettingsView: View {
    let browser: BrowserModel

    private var settings: HibernationSettings { browser.preferences.hibernation }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: binding(\.isEnabled)) {
                    Text("Sleep inactive tabs")
                    Text("Free memory by unloading tabs you have not used for a while. They reload where you left off.")
                }
                .accessibilityIdentifier("settings.hibernation.enabled")
                Picker("Sleep after", selection: binding(\.idleLimit)) {
                    ForEach(HibernationSettings.idleLimitOptions, id: \.self) { limit in
                        Text(limit.formatted(.units(allowed: [.hours, .minutes], width: .wide))).tag(limit)
                    }
                }
                .disabled(!settings.isEnabled)
                .accessibilityIdentifier("settings.hibernation.idleLimit")
                Toggle("Keep pinned tabs awake", isOn: binding(\.keepsPinnedTabsLoaded))
                    .disabled(!settings.isEnabled)
                    .accessibilityIdentifier("settings.hibernation.keepsPinned")
            } footer: {
                Text("Tabs that play media, use the camera or microphone, are in full screen, or contain unsent text stay awake. When the Mac runs low on memory, inactive tabs sleep sooner.")
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<HibernationSettings, Value>) -> Binding<Value> {
        Binding {
            settings[keyPath: keyPath]
        } set: { value in
            var updated = settings
            updated[keyPath: keyPath] = value
            browser.setHibernation(updated)
        }
    }
}
