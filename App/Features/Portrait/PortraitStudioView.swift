import AppKit
import BrowserCore
import SwiftUI

/// The studio over the window: the portrait as it will be, the choices that shape it beside it, and the ways out
/// below. Return copies it, ⌘S saves it, dragging the preview drops it anywhere. See docs/PORTRAIT.md.
struct PortraitStudioView: View {
    private static let controlsWidth: CGFloat = 272
    private static let maximumSize = CGSize(width: 1000, height: 700)

    let browser: BrowserModel
    let studio: PortraitStudio
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PortraitPreview(studio: studio, inset: 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ScrollView {
                    PortraitControls(studio: studio)
                        .padding(20)
                }
                .scrollIndicators(.never)
                .frame(width: Self.controlsWidth)
            }
            Divider()
            HStack(spacing: 8) {
                PortraitStatus(studio: studio, showsTitle: true)
                Spacer(minLength: 12)
                PromptCancelButton { browser.dismissPrompt() }
                PortraitActions(studio: studio, compact: false, close: close)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: Self.maximumSize.width, maxHeight: Self.maximumSize.height)
        .browserSurface(fill: palette.raised, border: palette.line, radius: BrowserDesign.Radius.window)
        .panelShadow()
        .padding(32)
        .tint(browser.accent.tint)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(BrowserCommand.capturePortrait.title)
        .accessibilityIdentifier("portrait")
    }

    /// Unless another prompt took its place meanwhile.
    private func close() {
        if case .portrait(let shown) = browser.window.prompt, shown === studio { browser.dismissPrompt() }
    }
}

/// What went wrong, else the picture's size.
struct PortraitStatus: View {
    let studio: PortraitStudio
    let showsTitle: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        if let failure = studio.failure {
            Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                .font(BrowserDesign.Typography.label)
                .foregroundStyle(palette.miss)
                .lineLimit(2)
                .accessibilityIdentifier("portrait.failure")
        } else {
            let size = studio.pixelSize
            VStack(alignment: .leading, spacing: 2) {
                if showsTitle { Text(verbatim: studio.title).font(BrowserDesign.Typography.label).lineLimit(1) }
                Text("\(Int(size.width)) × \(Int(size.height)) pixels")
                    .font(BrowserDesign.Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(palette.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Share, Save… and Copy, the ways out of both flows. Return and ⌘C copy, ⌘S saves; copying and saving end with
/// `close`.
struct PortraitActions: View {
    /// How long Copied shows before the picture's view closes.
    private static let copiedPause = Duration.milliseconds(650)

    let studio: PortraitStudio
    /// Share and Save as symbols, for the quick popover.
    let compact: Bool
    let close: @MainActor @Sendable () -> Void
    @State private var shareAnchor = PortraitAnchor()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Button(action: share) { Label("Share", systemImage: "square.and.arrow.up").labelStyle(.iconOnly) }
                .buttonStyle(PanelButtonStyle())
                .background(PortraitAnchorView(anchor: shareAnchor))
                .tooltip(String(localized: "Share"))
                .accessibilityIdentifier("portrait.share")
            Button { studio.save(in: scheme, saved: close) } label: {
                if compact { Label("Save…", systemImage: "square.and.arrow.down").labelStyle(.iconOnly) }
                else { HStack(spacing: 8) { Text("Save…"); Keycaps(KeyboardShortcut("s")) } }
            }
            .buttonStyle(PanelButtonStyle())
            .keyboardShortcut("s")
            .tooltip(String(localized: "Save…"), shortcut: compact ? KeyboardShortcut("s") : nil)
            .accessibilityIdentifier("portrait.save")
            Button(action: copy) {
                HStack(spacing: 8) {
                    if studio.copied { Label("Copied", systemImage: "checkmark") } else { Text("Copy") }
                    Keycaps(.defaultAction, onAccent: true)
                }
            }
            .buttonStyle(PanelButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
            // ⌘C copies too, as it would anything selected; behind the button, so it takes no room in the row.
            .background {
                Button("Copy", action: copy)
                    .keyboardShortcut("c")
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityIdentifier("portrait.copy")
        }
        .disabled(!studio.isReady)
    }

    /// Once: a second Return while Copied shows does nothing.
    private func copy() {
        guard studio.isReady, !studio.copied else { return }
        Task {
            guard await studio.copy(in: scheme) else { return }
            try? await Task.sleep(for: Self.copiedPause)
            close()
        }
    }

    private func share() {
        guard let anchor = shareAnchor.view else { return }
        studio.share(in: scheme, from: anchor)
    }
}

/// The portrait, scaled to fit, over a checkerboard where it is transparent. Dragging it out drops the picture.
struct PortraitPreview: View {
    let studio: PortraitStudio
    let inset: CGFloat
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { area in
            let canvas = studio.layout.canvas
            let room = CGSize(width: max(area.size.width - 2 * inset, 1), height: max(area.size.height - 2 * inset, 1))
            let scale = min(room.width / canvas.width, room.height / canvas.height, 1)
            ZStack {
                if studio.style.backdrop == .clear { Checkerboard().clipShape(RoundedRectangle(cornerRadius: 6)) }
                studio.canvas(in: scheme, zoom: scale)
                    .overlay(alignment: .topLeading) {
                        if studio.shot == nil {
                            let window = studio.layout.window
                            PortraitShimmer(radius: studio.style.cornerRadius * scale)
                                .frame(width: window.width * scale, height: window.height * scale)
                                .offset(x: window.minX * scale, y: window.minY * scale)
                                .transition(.opacity)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay { if studio.isLoadingFullPage { ProgressView().controlSize(.small) } }
            }
            .frame(width: canvas.width * scale, height: canvas.height * scale)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .onDrag { studio.dragItem(in: scheme) }
            .frame(width: area.size.width, height: area.size.height)
            // The layout's changes, not the colors', which follow the slider at once.
            .browserAnimation(value: studio.layout)
            .pageRevealAnimation(value: studio.shot != nil)
        }
        .background(palette.canvas)
        .accessibilityElement()
        .accessibilityLabel("Preview")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("portrait.preview")
    }
}

/// The choices, grouped as they shape the picture: what of the page, behind it, around it, on it.
private struct PortraitControls: View {
    let studio: PortraitStudio
    @Environment(\.palette) private var palette

    var body: some View {
        let style = studio.style
        VStack(alignment: .leading, spacing: 20) {
            section("Capture") {
                Picker("Capture", selection: binding(\.source)) {
                    Text("Visible area").tag(PortraitStyle.Source.visible)
                    Text("Full page").tag(PortraitStyle.Source.fullPage)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("portrait.source")
            }
            section("Background") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    ForEach(PortraitStyle.Backdrop.allCases) { backdrop in
                        BackdropTile(studio: studio, backdrop: backdrop, selected: style.backdrop == backdrop) {
                            studio.style.backdrop = backdrop
                        }
                    }
                }
                if style.backdrop.isTinted {
                    PortraitTintPicker(tint: binding(\.tint)).padding(.top, 4)
                } else if style.backdrop == .wallpaper {
                    Toggle("Blur", isOn: binding(\.blursWallpaper))
                }
            }
            section("Frame") {
                Picker("Size", selection: binding(\.aspect)) {
                    ForEach(PortraitStyle.Aspect.allCases) { aspect in Text(aspect.title).tag(aspect) }
                }
                .accessibilityIdentifier("portrait.aspect")
                labeledSlider("Padding", value: binding(\.padding), in: PortraitStyle.paddingRange)
                labeledSlider("Corners", value: binding(\.cornerRadius), in: PortraitStyle.cornerRange)
                labeledSlider("Shadow", value: binding(\.shadow), in: 0...1)
            }
            section("Show") {
                Toggle("Address bar", isOn: binding(\.showsAddress)).accessibilityIdentifier("portrait.address")
                Toggle("Captured with Aero", isOn: binding(\.showsCredit)).accessibilityIdentifier("portrait.credit")
            }
        }
        .toggleStyle(TrailingSwitchStyle())
        .controlSize(.small)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PortraitStyle, Value>) -> Binding<Value> {
        Binding(get: { studio.style[keyPath: keyPath] }, set: { studio.style[keyPath: keyPath] = $0 })
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BrowserDesign.Typography.label)
                .foregroundStyle(palette.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func labeledSlider(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 64, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
            Slider(value: value, in: range) { Text(title) }.labelsHidden()
        }
    }
}

extension PortraitStyle.Aspect {
    var title: LocalizedStringKey {
        switch self {
        case .fit: "Fit the page"
        case .square: "Square"
        case .widescreen: "Widescreen (16:9)"
        case .standard: "Standard (4:3)"
        case .portrait: "Portrait (4:5)"
        case .story: "Story (9:16)"
        }
    }
}

extension PortraitStyle.Backdrop {
    var title: LocalizedStringKey {
        switch self {
        case .gradient: "Gradient"
        case .aurora: "Aurora"
        case .solid: "Solid"
        case .wallpaper: "Desktop"
        case .site: "Site"
        case .clear: "None"
        }
    }
}

/// A backdrop, as a swatch of itself under its name.
struct BackdropTile: View {
    let studio: PortraitStudio
    let backdrop: PortraitStyle.Backdrop
    let selected: Bool
    /// A swatch alone, named by its tooltip, for the quick popover.
    var compact = false
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            VStack(spacing: 5) {
                swatch
                    .frame(height: compact ? 28 : 38)
                    .frame(maxWidth: .infinity)
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(palette.line) }
                    .padding(2)
                    .overlay { if selected { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.tint, lineWidth: 2) } }
                if !compact {
                    Text(backdrop.title)
                        .font(BrowserDesign.Typography.caption)
                        .foregroundStyle(selected ? palette.ink : palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(Text(backdrop.title))
        .accessibilityLabel(Text(backdrop.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("portrait.backdrop.\(backdrop.rawValue)")
    }

    /// The current style on this backdrop, so the swatches follow the tint.
    private var style: PortraitStyle {
        var style = studio.style
        style.backdrop = backdrop
        return style
    }

    @ViewBuilder private var swatch: some View {
        switch backdrop {
        case .clear: Checkerboard()
        case .wallpaper where studio.wallpaper == nil:
            Image(systemName: "photo").foregroundStyle(palette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.fill)
        default:
            GeometryReader { area in
                PortraitBackdrop(style: style, size: area.size, wallpaper: studio.wallpaper, siteColor: studio.siteColor)
            }
        }
    }
}

/// The tint: a rainbow of hues between the two neutrals, as Arc offered it.
struct PortraitTintPicker: View {
    private static let trackHeight: CGFloat = 20
    private static let knob: CGFloat = 24
    private static let step = 0.02

    @Binding var tint: PortraitStyle.Tint
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            neutral(.white, fill: Color(white: 0.97), label: "White")
            GeometryReader { area in
                let width = area.size.width
                let travel = max(width - Self.trackHeight, 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: stride(from: 0.0, through: 1, by: 1.0 / 12).map {
                            PortraitBackdrop.solid(.hue($0))
                        }, startPoint: .leading, endPoint: .trailing))
                        .overlay { Capsule().strokeBorder(.black.opacity(0.08)) }
                    if case .hue(let hue) = tint {
                        Circle()
                            .fill(.white)
                            .overlay { Circle().fill(PortraitBackdrop.solid(tint)).padding(5) }
                            .frame(width: Self.knob, height: Self.knob)
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                            .offset(x: Self.trackHeight / 2 + travel * hue - Self.knob / 2)
                    }
                }
                .frame(height: Self.trackHeight)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    tint = .hue(min(max((drag.location.x - Self.trackHeight / 2) / travel, 0), 1))
                })
            }
            .frame(height: Self.knob)
            .accessibilityElement()
            .accessibilityLabel("Color")
            .accessibilityValue(Text(hueValue.formatted(.percent.precision(.fractionLength(0)))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: tint = .hue(min(hueValue + Self.step, 1))
                case .decrement: tint = .hue(max(hueValue - Self.step, 0))
                @unknown default: break
                }
            }
            .accessibilityIdentifier("portrait.tint")
            neutral(.black, fill: Color(white: 0.1), label: "Black")
        }
    }

    private var hueValue: Double {
        if case .hue(let hue) = tint { return hue }
        return 0
    }

    private func neutral(_ value: PortraitStyle.Tint, fill: Color, label: LocalizedStringKey) -> some View {
        Button { tint = value } label: {
            Circle()
                .fill(fill)
                .overlay { Circle().strokeBorder(palette.line) }
                .padding(2)
                .overlay { if tint == value { Circle().strokeBorder(.tint, lineWidth: 2) } }
                .frame(width: Self.knob, height: Self.knob)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(tint == value ? .isSelected : [])
    }
}

/// A switch at the trailing edge, under the label's column.
private struct TrailingSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.lineLimit(1)
            Spacer(minLength: 8)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

/// A light sweeping across the empty frame while the snapshot is taken; a spinner with Reduce Motion. It runs only
/// until the picture arrives, which removes it.
private struct PortraitShimmer: View {
    private static let sweep = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: false)

    let radius: CGFloat
    @State private var sweeping = false
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { area in
            if reduceMotion {
                ProgressView().controlSize(.small).frame(width: area.size.width, height: area.size.height)
            } else {
                let band = max(area.size.width * 0.5, 40)
                LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: band, height: area.size.height)
                    .offset(x: sweeping ? area.size.width : -band)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Self.sweep) { sweeping = true }
        }
    }
}

/// Transparency, as image editors show it.
private struct Checkerboard: View {
    private static let square: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.96)))
            let columns = Int((size.width / Self.square).rounded(.up)), rows = Int((size.height / Self.square).rounded(.up))
            var squares = Path()
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    squares.addRect(CGRect(x: CGFloat(column) * Self.square, y: CGFloat(row) * Self.square, width: Self.square, height: Self.square))
                }
            }
            context.fill(squares, with: .color(Color(white: 0.86)))
        }
        .accessibilityHidden(true)
    }
}

/// The share button's view, which the system's share menu hangs from.
private final class PortraitAnchor {
    weak var view: NSView?
}

private struct PortraitAnchorView: NSViewRepresentable {
    let anchor: PortraitAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}
