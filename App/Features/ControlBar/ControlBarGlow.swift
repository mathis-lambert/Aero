import SwiftUI

extension View {
    /// `delay` after the bar appears, a band of light crosses it from bottom to top, then settles into a
    /// still ring and halo. With Reduce Motion the bar appears settled.
    func controlBarGlow(accent: Color, cornerRadius: CGFloat, delay: TimeInterval) -> some View {
        modifier(ControlBarGlow(accent: accent, cornerRadius: cornerRadius, delay: delay))
    }
}

private struct ControlBarGlow: ViewModifier {
    /// Quick to start, unhurried to finish.
    private static let crossing = Animation.timingCurve(0.15, 0.9, 0.3, 1, duration: 0.9)

    let accent: Color
    let cornerRadius: CGFloat
    let delay: TimeInterval
    @State private var progress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(GlowLight(progress: progress, accent: accent, cornerRadius: cornerRadius))
            .task {
                guard !reduceMotion else { progress = 1; return }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                withAnimation(Self.crossing) { progress = 1 }
            }
    }
}

/// Everything the crossing changes, derived from one progress value, so it only renders while it runs.
private struct GlowLight: ViewModifier, @MainActor Animatable {
    private static let haloBlur: CGFloat = 18
    private static let haloSpread: CGFloat = 2
    private static let ringWidth: CGFloat = 1
    private static let settledHalo = 0.12
    private static let settledRing = 0.4
    private static let flare = 0.2
    private static let kick = 0.005
    /// Half the band's height, as a share of the bar's height.
    private static let band = 0.6

    var progress: Double
    let accent: Color
    let cornerRadius: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let passing = sin(.pi * progress)
        // The settled light fades in behind the band, which travels from below the bar to above it.
        let settled = min(1, progress * 3)
        let center = 1 + Self.band - progress * (1 + 2 * Self.band)
        let light = accent.mix(with: .white, by: 0.5)
        let wave = LinearGradient(colors: [.clear, accent, light, accent, .clear],
                                  startPoint: UnitPoint(x: 0.5, y: center + Self.band),
                                  endPoint: UnitPoint(x: 0.5, y: center - Self.band))
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .background {
                ZStack {
                    shape.fill(accent).opacity(Self.settledHalo * settled)
                    shape.fill(wave).opacity(Self.flare * passing)
                }
                .blur(radius: Self.haloBlur)
                .padding(-Self.haloSpread)
            }
            .overlay {
                ZStack {
                    shape.strokeBorder(accent, lineWidth: Self.ringWidth).opacity(Self.settledRing * settled)
                    shape.strokeBorder(wave, lineWidth: Self.ringWidth * 1.5).opacity(passing)
                }
            }
            .scaleEffect(1 + Self.kick * passing)
    }
}
