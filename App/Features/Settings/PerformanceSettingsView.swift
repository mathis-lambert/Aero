import BrowserCore
import SwiftUI

struct PerformanceSettingsView: View {
    let browser: BrowserModel

    private var settings: HibernationSettings { browser.preferences.hibernation }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsRow("Sleep inactive tabs", caption: "Free memory by unloading tabs you have not used for a while. They reload where you left off.") {
                        Toggle("Sleep inactive tabs", isOn: binding(\.isEnabled))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityIdentifier("settings.hibernation.enabled")
                    }
                    SettingsDivider()
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
                    SettingsDivider()
                    SettingsRow("Keep pinned tabs awake") {
                        Toggle("Keep pinned tabs awake", isOn: binding(\.keepsPinnedTabsLoaded))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityIdentifier("settings.hibernation.keepsPinned")
                    }
                    .disabled(!settings.isEnabled)
                }
            }
            Text("Tabs that play media, use the camera or microphone, are in full screen, or contain unsent text stay awake. When the Mac runs low on memory, inactive tabs sleep sooner.")
                .font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
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
