import AppKit
import SwiftUI

/// What the wind writes: words, the brand's feather, rings around a point, or the New Tab crescent, in the view's points.
struct WindShape: Equatable {
    struct Word: Equatable {
        var text: String
        var center: CGPoint
        var size: CGFloat
        var maxWidth: CGFloat
        /// Symbols such as ⌘ come from the system face.
        var system = false
    }
    var words: [Word] = []
    var ringsAround: CGPoint?
    /// Where the feather goes; it spans the rectangle's shorter side.
    var feather: CGRect?
    var crescent = false

    static let none = WindShape()
}

/// A ripple crossing the field from a point.
struct WindRipple: Equatable {
    let id = UUID()
    var origin: CGPoint
    var strength: Double = 1
}

/// The onboarding's wind (`OnboardingWind.metal`). It drifts at 30 frames per second while the person interacts and
/// rests 20 seconds after the last `activity`; morphs, gusts and ripples run at the display cadence. It holds still while
/// the window is inactive, in Low Power Mode and with Reduce Motion, where shapes appear without motion.
struct OnboardingWind: View {
    private static let pitch: CGFloat = 6
    private static let driftInterval: TimeInterval = 1.0 / 30
    private static let restDelay = Duration.seconds(20)
    private static let morphDuration: TimeInterval = 1.9

    let shape: WindShape
    let ink: Color
    let paper: Color
    /// Toward paper: 0 on brand moments, higher when a picture sits on the stage.
    let fade: Double
    /// How dense the field stays outside the shape.
    let back: Double
    /// Changes on each step: a gust along the wind, forward or back.
    let gust: Int
    let gustsForward: Bool
    let ripple: WindRipple?
    /// Changes when the person does something.
    let activity: Int

    @State private var motion = WindMotion()
    @State private var oldMask: Image?
    @State private var newMask: Image?
    @State private var resting = false
    @State private var lively = false
    @State private var hoverActivity = 0
    @Environment(\.displayScale) private var displayScale
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.browserReduceMotion) private var reduceMotion

    private var allowsMotion: Bool { !reduceMotion && activeState != .inactive }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: lively ? nil : Self.driftInterval, paused: !allowsMotion || (resting && !lively))) { timeline in
                let frame = motion.advance(to: timeline.date, flowing: allowsMotion && !resting, allowsMotion: allowsMotion)
                Rectangle().fill(paper).colorEffect(ShaderLibrary.onboardingWind(
                    .float2(proxy.size), .float(Self.pitch), .float(1 / displayScale), .float(frame.time),
                    .float2(frame.shift), .float2(frame.pointer), .float(frame.near), .float(fade), .float(back),
                    .float(frame.morph), .color(ink), .color(paper),
                    .image(oldMask ?? Self.blank), .image(newMask ?? Self.blank), .floatArray(frame.ripples)))
            }
            .onChange(of: shape, initial: true) { _, shape in morph(to: shape, size: proxy.size) }
            .onChange(of: proxy.size) { _, size in
                newMask = Self.render(shape, size: size)
                oldMask = nil
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): motion.hover(at: location); hoverActivity += 1
                case .ended: motion.hover(at: nil)
                }
            }
        }
        .onChange(of: gust) { motion.gust(forward: gustsForward); beLively(for: 1.6) }
        .onChange(of: ripple) { _, ripple in
            guard let ripple, allowsMotion else { return }
            motion.ripple(ripple)
            beLively(for: 1.7)
        }
        .task(id: [activity, hoverActivity, gust]) {
            resting = false
            motion.wake()
            do { try await Task.sleep(for: Self.restDelay) } catch { return }
            resting = true
        }
        .allowsHitTesting(true)
        .accessibilityHidden(true)
    }

    private func morph(to shape: WindShape, size: CGSize) {
        oldMask = newMask
        newMask = Self.render(shape, size: size)
        guard allowsMotion else { motion.settleMorph(); return }
        motion.startMorph(duration: Self.morphDuration)
        beLively(for: Self.morphDuration)
    }

    private func beLively(for duration: TimeInterval) {
        lively = true
        Task {
            try? await Task.sleep(for: .seconds(duration))
            if !motion.isLively(at: .now) { lively = false }
        }
    }

    /// A real one-pixel black bitmap: an image without pixels cannot become the shader's texture.
    private static let blank: Image = render(.none, size: CGSize(width: 1, height: 1))

    /// White on black at one pixel per point: the shader samples it at each dot's center.
    static func render(_ shape: WindShape, size: CGSize) -> Image {
        let width = max(1, Int(size.width)), height = max(1, Int(size.height))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return Image(nsImage: NSImage(size: NSSize(width: 1, height: 1))) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Top-left origin, like the view.
        context.cgContext.translateBy(x: 0, y: CGFloat(height))
        context.cgContext.scaleBy(x: 1, y: -1)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.white.setFill(); NSColor.white.setStroke()
        for word in shape.words { draw(word, in: context) }
        if let feather = shape.feather { BrandFeather.draw(in: context.cgContext, rect: feather) }
        if let center = shape.ringsAround {
            for (index, radius) in [150.0, 214, 284, 360, 442].enumerated() {
                let path = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                path.lineWidth = 12 - Double(index) * 1.8
                NSColor(white: 0.8 - Double(index) * 0.15, alpha: 1).setStroke()
                path.stroke()
            }
        }
        if shape.crescent {
            let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: size.width * 0.7, y: size.height * 1.58), radius: size.height * 0.74,
                           startAngle: 216, endAngle: 324)
            path.lineWidth = 70; path.lineCapStyle = .round
            NSColor.white.setStroke(); path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return Image(nsImage: image)
    }

    /// Centered on its point, shrunk to fit its width.
    private static func draw(_ word: WindShape.Word, in context: NSGraphicsContext) {
        guard !word.text.isEmpty else { return }
        var size = word.size
        func font(_ size: CGFloat) -> NSFont { word.system ? .systemFont(ofSize: size, weight: .regular) : BrandType.titleFont(size) }
        var text = NSAttributedString(string: word.text, attributes: [.font: font(size), .foregroundColor: NSColor.white])
        if text.size().width > word.maxWidth {
            size *= word.maxWidth / text.size().width
            text = NSAttributedString(string: word.text, attributes: [.font: font(size), .foregroundColor: NSColor.white])
        }
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let cg = context.cgContext
        cg.saveGState()
        // Text draws in a bottom-left space: flip back locally around the word's center.
        cg.translateBy(x: word.center.x - bounds.midX, y: word.center.y + bounds.midY)
        cg.scaleBy(x: 1, y: -1)
        cg.textPosition = .zero
        CTLineDraw(line, cg)
        cg.restoreGState()
    }
}

/// The wind's own clock and forces, advanced frame by frame; it stops while the wind rests.
private final class WindMotion {
    private static let settle: TimeInterval = 20
    private static let windAngle = 24.0 * .pi / 180
    private var last: Date?
    private var time = 0.0
    private var shift = CGVector.zero
    private var speed = 0.0
    private var flow = 0.0
    private var near = 0.0
    private var pointer = CGPoint(x: -1e4, y: -1e4)
    private var hovering = false
    private var lastMove = Date.distantPast
    private var nextGust = Date.distantFuture
    private var push: (from: CGVector, to: CGVector, start: Date)?
    private var ripples: [(ripple: WindRipple, start: Date)] = []
    private var morphStart = Date.distantPast
    private var morphDuration: TimeInterval = 1

    struct Frame {
        var time: Float
        var shift: CGPoint
        var pointer: CGPoint
        var near: Float
        var morph: Float
        var ripples: [Float]
    }

    func wake() { nextGust = .now.addingTimeInterval(2) }

    func hover(at location: CGPoint?) {
        hovering = location != nil
        if let location { pointer = location; lastMove = .now }
    }

    func gust(forward: Bool) {
        speed += 1.1
        let distance = 90.0 * (forward ? 1 : -1)
        push = (shift, CGVector(dx: shift.dx + cos(Self.windAngle) * distance, dy: shift.dy + sin(Self.windAngle) * distance), .now)
    }

    func ripple(_ ripple: WindRipple) {
        ripples.append((ripple, .now))
        if ripples.count > 3 { ripples.removeFirst() }
    }

    func startMorph(duration: TimeInterval) { morphStart = .now; morphDuration = duration }
    func settleMorph() { morphStart = .distantPast }

    func isLively(at date: Date) -> Bool {
        date.timeIntervalSince(morphStart) < morphDuration || ripples.contains { date.timeIntervalSince($0.start) < 1.6 } || speed > 0.08
    }

    func advance(to date: Date, flowing: Bool, allowsMotion: Bool) -> Frame {
        let dt = min(0.05, max(0, date.timeIntervalSince(last ?? date)))
        last = date
        let moving = date.timeIntervalSince(lastMove) < 1.4
        flow += ((flowing ? 1 : 0) - flow) * min(1, dt * (flowing ? 1.5 : 0.6))
        near += ((hovering && date.timeIntervalSince(lastMove) < 2.6 ? 1 : 0) - near) * min(1, dt * 3.5)
        speed *= exp(-dt * 1.4)
        // The mistral: now and then a gust, between them a steady push along the wind.
        if flowing, date > nextGust { speed += 0.5 + .random(in: 0...0.7); nextGust = date.addingTimeInterval(.random(in: 3.5...8.5)) }
        let travel = dt * (34 * flow + 70 * speed)
        shift.dx += cos(Self.windAngle) * travel
        shift.dy += sin(Self.windAngle) * travel
        time += dt * ((moving ? 0.3 : 0) + speed * 0.8 + 0.22 * flow)
        var current = CGPoint(x: shift.dx, y: shift.dy)
        if let push {
            let k = min(1, date.timeIntervalSince(push.start) / 1.5), eased = 1 - pow(1 - k, 3)
            let offset = CGVector(dx: (push.to.dx - push.from.dx) * eased, dy: (push.to.dy - push.from.dy) * eased)
            if k >= 1 {
                self.push = nil
                shift.dx += offset.dx; shift.dy += offset.dy
            }
            current.x += offset.dx; current.y += offset.dy
        }
        return frame(date, shift: current, allowsMotion: allowsMotion)
    }

    private func frame(_ date: Date, shift: CGPoint, allowsMotion: Bool) -> Frame {
        ripples.removeAll { date.timeIntervalSince($0.start) > 1.6 }
        var values: [Float] = []
        for (ripple, start) in ripples {
            let k = min(1, date.timeIntervalSince(start) / 1.6)
            values += [Float(ripple.origin.x), Float(ripple.origin.y), Float((1 - pow(1 - k, 3)) * 900), Float(ripple.strength * pow(1 - k, 1.6))]
        }
        if values.isEmpty { values = [0, 0, 0, 0] }
        let morph = allowsMotion ? min(1, max(0, date.timeIntervalSince(morphStart) / morphDuration)) : 1
        return Frame(time: Float(time), shift: shift, pointer: pointer, near: Float(near), morph: Float(morph), ripples: values)
    }
}
