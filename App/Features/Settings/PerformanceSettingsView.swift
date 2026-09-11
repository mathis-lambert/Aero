import BrowserCore
import SwiftUI

struct PerformanceSettingsView: View {
    let browser: BrowserModel

    private var settings: HibernationSettings { browser.preferences.hibernation }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsRow("Sleep inactive tabs", caption: "Free memory by unloading tabs you have not used for a while. They reload where you left off.") {
                        Toggle("Sleep inactive tabs", isOn: binding(\.isEnabled))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityIdentifier("settings.hibernation.enabled")
                    }
                    Divider().padding(.vertical, 12)
                    SettingsRow("Sleep after") {
                        Picker("Sleep after", selection: binding(\.idleLimit)) {
                            ForEach(HibernationSettings.idleLimitOptions, id: \.self) { limit in
                                Text(limit.formatted(.units(allowed: [.hours, .minutes], width: .wide))).tag(limit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: SettingsLayout.pickerWidth, alignment: .trailing)
                        .accessibilityIdentifier("settings.hibernation.idleLimit")
                    }
                    .disabled(!settings.isEnabled)
                    Divider().padding(.vertical, 12)
                    SettingsRow("Keep pinned tabs awake") {
                        Toggle("Keep pinned tabs awake", isOn: binding(\.keepsPinnedTabsLoaded))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityIdentifier("settings.hibernation.keepsPinned")
                    }
                    .disabled(!settings.isEnabled)
                }
            }
            Label("Tabs that play media, use the camera or microphone, are in full screen, or contain unsent text stay awake. When the Mac runs low on memory, inactive tabs sleep sooner.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
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
