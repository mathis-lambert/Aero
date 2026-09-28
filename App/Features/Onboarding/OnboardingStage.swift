import AppKit
import BrowserCore
import BrowserStorage
import SwiftUI

/// What each step shows on the stage, over the wind, in the room the step's shape leaves; every picture is scaled to
/// fit it, so the stage holds at any window size. Previews of the browser use the chrome's type and colors.
struct OnboardingStage: View {
    let browser: BrowserModel
    let onboarding: OnboardingModel
    let layout: OnboardingLayout
    @Environment(\.palette) private var palette

    var body: some View {
        let region = layout.stageRegion(for: onboarding.step)
        ZStack {
            switch onboarding.step {
            case .welcome: Color.clear
            case .source:
                StageFit(available: region.size) {
                    if onboarding.needsFullDiskAccess { fullDiskAccess } else {
                        SourceCovers(spaces: coverSpaces, fresh: onboarding.selectedSourceID == nil, countsFavorites: onboarding.source?.favorites != .unreadable)
                            .id(onboarding.selectedSourceID ?? "fresh")
                    }
                }
            case .choice:
                StageFit(available: region.size) { MappingCard(profiles: onboarding.preview ?? [], source: onboarding.source, choice: onboarding.choice) }
            case .importing, .gettingAround, .ready:
                let trying = onboarding.step == .gettingAround
                StageFit(available: region.size) {
                    OnboardingBrowserTwin(browser: browser, onboarding: onboarding,
                                          sidebarShown: !(trying && onboarding.lastTried == .toggleSidebar),
                                          controlBarShown: trying && onboarding.lastTried == .commandPalette,
                                          recentTabTries: onboarding.recentTabTries)
                }
            case .defaultBrowser: StageFit(available: region.size) { AppIconPlate(isDefault: onboarding.isDefaultBrowser) }
            }
        }
        .frame(width: region.width, height: region.height)
        .position(x: region.midX, y: region.midY)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        // One browser preview from the import to the end: it moves and changes, and is never rebuilt.
        .id(Self.scene(of: onboarding.step))
        .browserAnimation(value: region)
        .browserAnimation(value: onboarding.step)
    }

    private static func scene(of step: OnboardingStep) -> String {
        switch step {
        case .importing, .gettingAround, .ready: "browser"
        default: step.rawValue
        }
    }

    private var coverSpaces: [(name: String, color: SpaceColor, favorites: Int)] {
        guard let profiles = onboarding.preview else { return [] }
        return profiles.flatMap(\.spaces).sorted { $0.position < $1.position }.enumerated().map { index, space in
            (space.name ?? "", space.color ?? SpaceColor.presets[index % SpaceColor.presets.count].color,
             space.allLinks.count)
        }
    }

    private var fullDiskAccess: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "lock").font(.system(size: 20)).foregroundStyle(palette.secondary).padding(.bottom, 4)
            Text("Safari keeps its data locked.").font(BrowserDesign.Typography.heading)
            Text("Allow Full Disk Access so Aero can read it. macOS asks Aero to reopen; you come back here.")
                .font(BrowserDesign.Typography.chrome).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
            Button("Open System Settings") { onboarding.openFullDiskAccessSettings() }
                .buttonStyle(PanelButtonStyle())
                .accessibilityIdentifier("onboarding.fullDiskAccess")
        }
        .padding(22)
        .frame(width: 320, alignment: .leading)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card).strokeBorder(palette.line))
        .shadow(color: .black.opacity(0.12), radius: 25, y: 18)
    }
}

// MARK: - Covers

/// A space's wind in its color: a still halftone, seeded by its name.
struct SpaceCover: View {
    let color: Color
    let seed: Int
    var pitch: CGFloat = 3.5

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            var dots = Path()
            let columns = Int(size.width / pitch) + 1, rows = Int(size.height / pitch) + 1
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = (CGFloat(column) + 0.5) * pitch, y = (CGFloat(row) + 0.5) * pitch
                    let dark = 1 - Self.field(x / 180 + Double(seed) * 1.7, y / 180)
                    let radius = sqrt(max(0, dark)) * pitch * 0.58
                    if radius > 0.3 { dots.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)) }
                }
            }
            context.fill(dots, with: .color(color))
        }
        .accessibilityHidden(true)
    }

    private static func hash(_ x: Double, _ y: Double) -> Double {
        let value = sin(x * 127.1 + y * 311.7) * 43758.5453
        return value - floor(value)
    }

    private static func noise(_ x: Double, _ y: Double) -> Double {
        let xi = floor(x), yi = floor(y), xf = x - xi, yf = y - yi
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
    }

    /// The mistral: a warped noise stretched along the wind.
    static func field(_ x: Double, _ y: Double) -> Double {
        func fbm(_ x: Double, _ y: Double) -> Double {
            var sum = 0.0, amplitude = 0.5, x = x, y = y
            for _ in 0..<4 { sum += amplitude * noise(x, y); x = x * 2.03 + 17.1; y = y * 2.03 + 3.7; amplitude *= 0.5 }
            return sum
        }
        let u = x * 0.9135 + y * 0.4067, v = -x * 0.4067 + y * 0.9135
        let px = u * 0.45 * 4, py = v * 1.6 * 4
        let qx = fbm(px, py), qy = fbm(px + 5.2, py + 1.3)
        return min(1, max(0, (fbm(px + 1.9 * qx, py + 1.9 * qy) - 0.5) * 1.3 + 0.5))
    }
}

/// The spaces the source holds, fanned out like a hand of cards from left to right, each one's name in view; they
/// arrive one after another and lean toward the pointer.
private struct SourceCovers: View {
    private static let cardWidth: CGFloat = 150
    private static let step: CGFloat = 118
    private static let size = CGSize(width: 560, height: 330)

    let spaces: [(name: String, color: SpaceColor, favorites: Int)]
    let fresh: Bool
    /// False for a browser whose favorites cannot be read.
    let countsFavorites: Bool
    @State private var arrived = false
    @State private var tilt = CGSize.zero
    @State private var hovered: Int?
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let shown = fresh ? [(name: String(localized: "Main"), color: SpaceColor.initial, favorites: 0)] : Array(spaces.prefix(4))
        ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, space in
                let k = CGFloat(index) - CGFloat(shown.count - 1) / 2
                let lifted = hovered == index
                card(space)
                    .shadow(color: .black.opacity(lifted ? 0.22 : 0.14), radius: lifted ? 26 : 18, y: lifted ? 20 : 14)
                    .scaleEffect(lifted ? 1.04 : 1)
                    .rotationEffect(.degrees(arrived ? Double(k) * 4 : 0), anchor: .bottom)
                    .offset(x: arrived ? k * Self.step : 0, y: (arrived ? abs(k) * 12 : 60) - (lifted ? 12 : 0))
                    .opacity(arrived ? 1 : 0)
                    // Each card lies over the one before it, so every name stays in view.
                    .zIndex(lifted ? 20 : Double(index))
                    .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                    .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.18).delay(Double(index) * 0.06), value: arrived)
                    .animation(BrowserDesign.hover, value: lifted)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .rotation3DEffect(.degrees(Double(-tilt.height) * 10), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
        .rotation3DEffect(.degrees(Double(tilt.width) * 14), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .animation(.spring(duration: 0.6, bounce: 0.1), value: tilt)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard !reduceMotion else { return }
            switch phase {
            case .active(let point): tilt = CGSize(width: point.x / Self.size.width - 0.5, height: point.y / Self.size.height - 0.5)
            case .ended: tilt = .zero
            }
        }
        .onAppear { arrived = true }
        .accessibilityElement(children: .combine)
    }

    private func card(_ space: (name: String, color: SpaceColor, favorites: Int)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SpaceCover(color: space.color.tint, seed: space.name.unicodeScalars.reduce(0) { $0 + Int($1.value) })
                .aspectRatio(4 / 5, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                .opacity(fresh ? 0.45 : 1)
                .padding(.bottom, 6)
            HStack(spacing: 6) {
                Circle().fill(space.color.tint).frame(width: 7, height: 7)
                Text(verbatim: space.name).font(BrowserDesign.Typography.chrome.weight(.medium)).lineLimit(1)
            }
            Group { if fresh { Text("Empty for now") } else if countsFavorites { Text("\(space.favorites) favorites") } else { Text("History and passwords") } }
                .font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(width: Self.cardWidth)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card).strokeBorder(palette.line))
    }
}

// MARK: - Mapping

/// How the source's spaces become Aero spaces: each row, the source's space and the Aero space it becomes, with the
/// profile that space uses.
private struct MappingCard: View {
    private static let shownRows = 6
    private static let aeroColumn: CGFloat = 220

    let profiles: [ImportedProfile]
    let source: ImportSource?
    let choice: ImportChoice
    @State private var arrived = false
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let rows = profiles.flatMap { profile in profile.spaces.map { (space: $0, profile: profile.name) } }.sorted { $0.space.position < $1.space.position }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let source { BrowserIcon(bundleIdentifier: source.bundleIdentifier).frame(width: 18, height: 18) }
                Text(verbatim: source.map(OnboardingView.shortName) ?? "")
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Image(nsImage: AppIconImage.current).resizable().frame(width: 18, height: 18)
                    Text(verbatim: "Aero")
                }
                .frame(width: Self.aeroColumn, alignment: .leading)
            }
            .font(BrowserDesign.Typography.label).foregroundStyle(palette.secondary)
            .padding(.horizontal, 16)
            .frame(height: 40)
            Hairline()
            VStack(spacing: 0) {
                ForEach(Array(rows.prefix(Self.shownRows).enumerated()), id: \.offset) { index, row in
                    let color = row.space.color ?? SpaceColor.presets[index % SpaceColor.presets.count].color
                    let name = row.space.name ?? row.profile
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: name).lineLimit(1)
                            Text(choice.favorites ? "\(row.space.allLinks.count) favorites" : "Empty")
                                .font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right").font(BrowserDesign.Typography.glyph).foregroundStyle(palette.secondary.opacity(0.7))
                        HStack(spacing: 8) {
                            Circle().fill(color.tint).frame(width: 8, height: 8)
                            Text(verbatim: name).lineLimit(1)
                            Spacer(minLength: 6)
                            Label { Text(verbatim: row.profile).lineLimit(1) } icon: { Image(systemName: "person.crop.circle") }
                                .labelStyle(.titleAndIcon)
                                .font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary)
                                .padding(.horizontal, 7).frame(height: 20)
                                .background(palette.fill, in: Capsule())
                        }
                        .padding(.horizontal, 10)
                        .frame(width: Self.aeroColumn, height: 34)
                        .background(color.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                    }
                    .font(BrowserDesign.Typography.chrome)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .opacity(arrived ? 1 : 0)
                    .offset(x: arrived ? 0 : -10)
                    .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.12).delay(Double(index) * 0.045), value: arrived)
                    if index < min(rows.count, Self.shownRows) - 1 { Hairline().padding(.leading, 16) }
                }
            }
            .padding(.vertical, 4)
            if rows.count > Self.shownRows {
                Text("And \(rows.count - Self.shownRows) more spaces")
                    .font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .frame(width: 500)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card + 4))
        .overlay(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card + 4).strokeBorder(palette.line))
        .panelShadow()
        .browserAnimation(value: choice.favorites)
        .onAppear { arrived = true }
    }
}

/// A site's initial on a tile, in a color of its own: favorites in flight have no saved icon yet.
struct LetterFavicon: View {
    let url: URL
    var body: some View {
        let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? "?"
        // Stable across launches, unlike `hashValue`.
        let hue = Double(host.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) / 360
        Text(verbatim: String(host.prefix(1)).uppercased())
            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Color(hue: hue, saturation: 0.55, brightness: 0.6), in: RoundedRectangle(cornerRadius: 16 * BrowserDesign.faviconCornerRatio))
            .accessibilityHidden(true)
    }
}

/// Lays a picture out at its own size, then scales it down, never up, to fit `available`.
struct StageFit<Content: View>: View {
    let available: CGSize
    @ViewBuilder var content: Content
    @State private var natural = CGSize.zero

    var body: some View {
        let scale = natural.width > 0 && natural.height > 0
            ? min(1, available.width / natural.width, available.height / natural.height) : 1
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { natural = $0 }
            .scaleEffect(scale)
            .frame(width: available.width, height: available.height)
            // Measured before it shows, so it never appears at the wrong size.
            .opacity(natural == .zero ? 0 : 1)
    }
}

/// Lays words out in lines, wrapping at the plate's width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat?

    /// Without a proposed width (some stacks ask first with none), lines wrap at this width, so the reported height
    /// matches what is placed.
    var fallbackWidth: CGFloat = 380

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? fallbackWidth
        return arrange(subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Wrap exactly as when measuring: the bounds are the measured width, which rounding could make wrap again.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? fallbackWidth
        for (index, point) in arrange(subviews, width: max(width, bounds.width)).points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width + 0.5 { x = 0; y += line + (lineSpacing ?? spacing); line = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing; line = max(line, size.height); widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: widest, height: y + line))
    }
}

// MARK: - Default browser

private struct AppIconPlate: View {
    let isDefault: Bool
    @State private var absorbed = false
    @Environment(\.brand) private var brand
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                // The ring that leaves the icon as it takes the links.
                RoundedRectangle(cornerRadius: 168 * 0.224).strokeBorder(.tint, lineWidth: 2)
                    .frame(width: 168, height: 168)
                    .scaleEffect(absorbed ? 1.45 : 1).opacity(absorbed ? 0 : (isDefault ? 0.9 : 0))
                    .animation(reduceMotion ? nil : .easeOut(duration: 1).delay(0.6), value: absorbed)
                Image(nsImage: AppIconImage.current).resizable().frame(width: 168, height: 168)
                    .keyframeAnimator(initialValue: 1.0, trigger: absorbed) { content, scale in content.scaleEffect(scale) } keyframes: { _ in
                        KeyframeTrack { CubicKeyframe(1, duration: 0.55); SpringKeyframe(1.07, duration: 0.25); SpringKeyframe(1, duration: 0.4) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(.tint, in: Circle())
                            .overlay(Circle().strokeBorder(brand.paper, lineWidth: 4))
                            .scaleEffect(isDefault ? 1 : 0.01).opacity(isDefault ? 1 : 0)
                            .animation(.spring(duration: 0.5, bounce: 0.3).delay(isDefault && !reduceMotion ? 0.7 : 0), value: isDefault)
                            .offset(x: 6, y: 6)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 25, y: 24)
            }
            HStack(spacing: 8) {
                ForEach(Array(["Mail", "Messages", "PDF"].enumerated()), id: \.offset) { index, name in
                    Label { Text(verbatim: name) } icon: { Image(systemName: "arrow.right") }
                        .labelStyle(.titleAndIcon)
                        .font(BrowserDesign.Typography.label).foregroundStyle(palette.secondary)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(brand.paper, in: Capsule()).overlay(Capsule().strokeBorder(palette.line))
                        // Drawn into the icon once Aero opens links.
                        .offset(x: absorbed ? CGFloat(1 - index) * 90 : 0, y: absorbed ? -110 : 0)
                        .scaleEffect(absorbed ? 0.2 : 1)
                        .opacity(absorbed ? 0 : 1)
                        .animation(reduceMotion ? nil : .timingCurve(0.55, 0, 0.75, 0.2, duration: 0.6).delay(0.12 + Double(index) * 0.09), value: absorbed)
                }
            }
        }
        .onChange(of: isDefault, initial: true) { _, isDefault in absorbed = isDefault }
    }
}
