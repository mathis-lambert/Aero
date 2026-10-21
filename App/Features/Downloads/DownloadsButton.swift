import AppKit
import BrowserWebKit
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar footer's downloads button: a pie fills its circle as active downloads progress, grey while they are all
/// paused, and the session's downloads open in a popover.
struct DownloadsButton: View {
    /// Inside the symbol's circle, clear of its stroke.
    private static let pieInset: CGFloat = 8.5

    let downloads: DownloadCoordinator
    @Binding var presented: Bool
    let shortcut: KeyboardShortcut?
    let toggle: () -> Void
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        IconButton(symbol: "arrow.down.circle", label: "Downloads", size: BrowserDesign.sidebarButtonSize, shortcut: shortcut, action: toggle)
            .overlay { if let progress { pie(progress) } }
            // Takes the hit as a new download's file lands: a kick, then a damped wobble on its base.
            .keyframeAnimator(initialValue: Landing(), trigger: reduceMotion ? nil : downloads.lastStarted) { [reduceMotion] button, landing in
                button
                    .scaleEffect(reduceMotion ? 1 : landing.scale, anchor: .bottom)
                    .rotationEffect(.degrees(reduceMotion ? 0 : landing.angle), anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: DownloadFlight.duration * 0.92)
                    SpringKeyframe(1.18, duration: 0.08)
                    SpringKeyframe(1, duration: 0.3, spring: .snappy)
                }
                KeyframeTrack(\.angle) {
                    LinearKeyframe(0, duration: DownloadFlight.duration * 0.92)
                    CubicKeyframe(-11, duration: 0.06)
                    CubicKeyframe(8, duration: 0.08)
                    CubicKeyframe(-4, duration: 0.08)
                    CubicKeyframe(1.5, duration: 0.08)
                    CubicKeyframe(0, duration: 0.08)
                }
            }
            .downloadsTarget()
            .accessibilityIdentifier("downloads.button")
            .popover(isPresented: $presented, arrowEdge: .top) {
                DownloadsList(downloads: downloads)
                    .onExitCommand { presented = false }
            }
    }

    private struct Landing {
        var scale = 1.0
        /// In degrees.
        var angle = 0.0
    }

    /// The share of bytes received of the downloads under way or paused whose size is known.
    private var progress: (fraction: Double, paused: Bool)? {
        let active = downloads.downloads.filter { ($0.state == .downloading || $0.state == .paused) && $0.totalBytes != nil }
        let total = active.reduce(0) { $0 + ($1.totalBytes ?? 0) }
        guard total > 0 else { return nil }
        let completed = active.reduce(0) { $0 + $1.completedBytes }
        return (min(1, Double(completed) / Double(total)), active.allSatisfy { $0.state == .paused })
    }

    private func pie(_ progress: (fraction: Double, paused: Bool)) -> some View {
        Pie(fraction: progress.fraction)
            .fill(progress.paused ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            .opacity(0.55)
            .padding(Self.pieInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A share of a circle, from twelve o'clock clockwise.
private struct Pie: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct DownloadsList: View {
    private static let width: CGFloat = 320
    private static let maximumVisibleRows: CGFloat = 5
    private static let rowHeight: CGFloat = 44

    let downloads: DownloadCoordinator
    @FocusState private var isFocused: Bool
    @State private var renaming: BrowserDownload.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloads").font(BrowserDesign.Typography.label).foregroundStyle(.secondary)
                Spacer()
                if downloads.downloads.contains(where: { $0.state != .downloading }) {
                    Button {
                        downloads.clearInactive()
                        // The Clear button disappears with the last row; retain an Escape responder.
                        isFocused = true
                    } label: {
                        Text("Clear").font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("downloads.clear")
                }
            }
            .padding(.horizontal, BrowserDesign.rowInset)
            if downloads.downloads.isEmpty {
                Text("No downloads")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .accessibilityIdentifier("downloads.empty")
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(downloads.downloads) { download in
                            DownloadRow(download: download, downloads: downloads, renaming: $renaming)
                                .frame(height: Self.rowHeight)
                        }
                    }
                }
                .frame(maxHeight: Self.rowHeight * Self.maximumVisibleRows)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .frame(width: Self.width)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .browserAnimation(value: downloads.downloads.map(\.id))
    }
}

/// A file type's Finder icon. Its own view, so progress updates of a row do not ask the system for it again.
struct FileIcon: View {
    let filename: String
    var size = BrowserDesign.downloadIconSize

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data))
            .resizable()
            .frame(width: size, height: size)
    }
}
