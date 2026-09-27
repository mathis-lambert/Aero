import SwiftUI

extension EnvironmentValues {
    @Entry var browserReduceMotion = false
}

extension View {
    /// Install once at each window root; descendants share the native accessibility and power policy.
    func browserMotionPreferences() -> some View {
        modifier(BrowserMotionPreferences())
    }
}

private struct BrowserMotionPreferences: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    func body(content: Content) -> some View {
        content
            .environment(\.browserReduceMotion, reduceMotion || lowPower)
            .onAppear { lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
                .receive(on: RunLoop.main)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}
