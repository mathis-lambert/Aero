import CoreGraphics
import Foundation

/// The wind's own clock and forces, advanced frame by frame; it stops while the wind rests.
final class WindMotion {
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
        var isLively: Bool
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

    private func isLively(at date: Date) -> Bool {
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
        return Frame(time: Float(time), shift: shift, pointer: pointer, near: Float(near), morph: Float(morph), isLively: isLively(at: date), ripples: values)
    }
}
