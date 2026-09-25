import SwiftUI

extension View {
    /// A short horizontal shake each time `trigger` changes, for input that found nothing.
    /// Skipped with Reduce Motion; the state change must also be shown without motion.
    func shake(trigger: Int) -> some View {
        modifier(ShakeEffect(trigger: trigger))
    }
}

private struct ShakeEffect: ViewModifier {
    private static let distance: CGFloat = 6
    private static let outDuration: TimeInterval = 0.06
    private static let backDuration: TimeInterval = 0.08
    private static let settleDuration: TimeInterval = 0.12

    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let distance = reduceMotion ? 0 : Self.distance
        return content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { content, offset in
            content.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(distance, duration: Self.outDuration)
                SpringKeyframe(-distance, duration: Self.backDuration)
                SpringKeyframe(0, duration: Self.settleDuration)
            }
        }
    }
}
