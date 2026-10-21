import SwiftUI

/// A group's folder, drawn in two layers so it can open: the back with its tab, outlined, and a translucent front flap
/// whose top edge drops and widens as the group opens, as a flap swinging toward the viewer, then closes back over the
/// back. Under the pointer a closed folder peeks: its flap opens a little, as its preview is about to show. The flap
/// is a vector shape whose openness animates, so it stays crisp at every step. With Reduce Motion it changes without
/// moving.
struct FolderIcon: View {
    private static let size = CGSize(width: 16, height: 13)
    private static let motion = Animation.spring(duration: 0.32, bounce: 0.12)
    private static let line: CGFloat = 1.3
    private static let bleed: CGFloat = 3
    /// A closed folder under the pointer opens this much of the way.
    private static let peek: Double = 0.35
    /// The back's and the flap's corners match, so a closed flap lies exactly on the back's lower body.
    fileprivate nonisolated static let radius: CGFloat = 2.2

    let isOpen: Bool
    var isPeeking = false
    var tint: Color = .secondary
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let openness = isOpen ? 1 : isPeeking ? Self.peek : 0
        // One shape tinted once, so the strokes where the layers meet never darken. The tint spreads past the folder,
        // for its strokes and the opening flap, which widens past it.
        tint.mask {
            ZStack {
                FolderBack()
                    .stroke(style: StrokeStyle(lineWidth: Self.line, lineJoin: .round))
                // The flap hides what of the back lies behind it, then draws itself.
                FolderFlap(openness: openness).blendMode(.destinationOut)
                FolderFlap(openness: openness)
                    .fill(.white.opacity(0.16 + 0.14 * openness))
                    .overlay { FolderFlap(openness: openness).stroke(style: StrokeStyle(lineWidth: Self.line, lineJoin: .round)) }
            }
            .compositingGroup()
            .frame(width: Self.size.width, height: Self.size.height)
        }
        .padding(-Self.bleed)
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(reduceMotion ? nil : Self.motion, value: openness)
        .accessibilityHidden(true)
    }
}

/// The front flap over the folder's lower body. Opening, its top edge drops and spreads past the sides, so the flap
/// reads as leaning toward the viewer; closed, it lies exactly on the back.
private struct FolderFlap: Shape {
    var openness: Double

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // The spring may overshoot; the flap never leans back past closed.
        let open = CGFloat(min(max(openness, 0), 1.2))
        let top = rect.minY + rect.height * (0.3 + 0.24 * open)
        let spread = rect.width * 0.09 * open
        let radius = FolderIcon.radius
        let topLeft = CGPoint(x: rect.minX - spread, y: top)
        let topRight = CGPoint(x: rect.maxX + spread, y: top)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: (topLeft.x + topRight.x) / 2, y: top))
        path.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: radius)
        path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: radius)
        path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: radius)
        path.addArc(tangent1End: topLeft, tangent2End: topRight, radius: radius)
        path.closeSubpath()
        return path
    }
}

/// The folder's back: a body with rounded corners and a tab on its leading top edge.
private struct FolderBack: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = FolderIcon.radius
        let tabWidth = rect.width * 0.42
        let shoulder = rect.height * 0.2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + tabWidth, y: rect.minY), radius: radius)
        path.addLine(to: CGPoint(x: rect.minX + tabWidth, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + tabWidth + shoulder, y: rect.minY + shoulder))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY + shoulder), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.closeSubpath()
        return path
    }
}
