import SwiftUI

/// A group's folder, drawn in two layers so it can open: the back with its tab, outlined, and a translucent front flap
/// that swings forward, in perspective, as the group opens, then closes back over it. With Reduce Motion the flap
/// changes without moving.
struct FolderIcon: View {
    fileprivate static let size = CGSize(width: 16, height: 13)
    /// The flap leans this far toward the viewer when open.
    fileprivate static let openAngle: Double = -48
    private static let motion = Animation.spring(duration: 0.4, bounce: 0.32)
    private static let line: CGFloat = 1.3
    private static let bleed: CGFloat = 3
    /// The back's and the flap's corners match, so a closed flap lies exactly on the back's lower body.
    fileprivate nonisolated static let radius: CGFloat = 2.2

    let isOpen: Bool
    var tint: Color = .secondary
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        // One shape tinted once, so the strokes where the layers meet never darken. The tint spreads past the folder,
        // for its strokes and the opening flap, which widens toward the viewer.
        tint.mask {
            ZStack(alignment: .bottom) {
                FolderBack()
                    .stroke(style: StrokeStyle(lineWidth: Self.line, lineJoin: .round))
                // The flap hides what of the back lies behind it, then draws itself.
                FlapShape().modifier(FlapPosition(isOpen: isOpen)).blendMode(.destinationOut)
                FlapShape()
                    .fill(.white.opacity(isOpen ? 0.3 : 0.16))
                    .overlay { FlapShape().stroke(lineWidth: Self.line) }
                    .modifier(FlapPosition(isOpen: isOpen))
            }
            .compositingGroup()
            .frame(width: Self.size.width, height: Self.size.height)
        }
        .padding(-Self.bleed)
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(reduceMotion ? nil : Self.motion, value: isOpen)
        .accessibilityHidden(true)
    }

    /// The flap's outline: rounded as the back is, so a closed flap lies exactly on its lower body.
    private struct FlapShape: Shape {
        func path(in rect: CGRect) -> Path {
            RoundedRectangle(cornerRadius: FolderIcon.radius, style: .continuous).path(in: rect)
        }
    }

    /// The flap's place: the back's lower body, leaning toward the viewer when open.
    fileprivate struct FlapPosition: ViewModifier {
        let isOpen: Bool

        func body(content: Content) -> some View {
            content
                .frame(height: FolderIcon.size.height * 0.7)
                .rotation3DEffect(.degrees(isOpen ? FolderIcon.openAngle : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.55)
        }
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
