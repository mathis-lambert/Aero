import AppKit
import BrowserWebKit
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar footer's downloads button: a ring shows the progress of active downloads, and the
/// session's downloads open in a popover.
struct DownloadsButton: View {
    private static let ringWidth: CGFloat = 1.5
    private static let ringInset: CGFloat = 5

    let downloads: DownloadCoordinator
    @State private var presented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        IconButton(symbol: "arrow.down.circle", label: "Downloads", size: BrowserDesign.navigationButtonSize) { presented.toggle() }
            .overlay { if let progress { ring(progress) } }
            // Takes the hit as a new download's file lands: a kick, then a damped wobble on its base.
            .keyframeAnimator(initialValue: Landing(), trigger: reduceMotion ? nil : downloads.lastStarted) { button, landing in
                button
                    .scaleEffect(landing.scale, anchor: .bottom)
                    .rotationEffect(.degrees(landing.angle), anchor: .bottom)
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
            .popover(isPresented: $presented, arrowEdge: .top) { DownloadsList(downloads: downloads) }
    }

    private struct Landing {
        var scale = 1.0
        /// In degrees.
        var angle = 0.0
    }

    /// The average progress of active downloads whose size is known.
    private var progress: Double? {
        let active = downloads.downloads.filter { $0.state == .downloading && $0.totalBytes != nil }
        guard !active.isEmpty else { return nil }
        return active.map(\.fractionCompleted).reduce(0, +) / Double(active.count)
    }

    private func ring(_ progress: Double) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(.tint, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(Self.ringInset)
            .allowsHitTesting(false)
    }
}

private struct DownloadsList: View {
    private static let width: CGFloat = 320
    private static let maximumVisibleRows: CGFloat = 5
    private static let rowHeight: CGFloat = 44

    let downloads: DownloadCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Downloads").font(BrowserDesign.Typography.label).foregroundStyle(.secondary)
                Spacer()
                if downloads.downloads.contains(where: { $0.state != .downloading }) {
                    Button { downloads.clearInactive() } label: {
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
                            DownloadRow(download: download, downloads: downloads)
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
        .browserAnimation(value: downloads.downloads.map(\.id))
    }
}

private struct DownloadRow: View {
    let download: BrowserDownload
    let downloads: DownloadCoordinator

    var body: some View {
        HStack(spacing: BrowserDesign.rowInset) {
            FileIcon(filename: download.filename)
                .opacity(download.state == .downloading ? 0.6 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: download.filename).lineLimit(1).truncationMode(.middle)
                if download.state == .downloading, download.totalBytes != nil {
                    ProgressView(value: download.fractionCompleted).progressViewStyle(.linear).controlSize(.mini)
                }
                status.font(BrowserDesign.Typography.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: 0)
            action
        }
        .padding(.horizontal, BrowserDesign.rowInset)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if download.state == .finished, let file = download.destination { NSWorkspace.shared.open(file) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloads.row")
    }

    private var status: Text {
        let completed = download.completedBytes.formatted(.byteCount(style: .file))
        switch download.state {
        case .downloading:
            if let total = download.totalBytes { return Text("\(completed) of \(total.formatted(.byteCount(style: .file)))") }
            return Text(verbatim: completed)
        case .finished: return Text(verbatim: completed)
        case .failed: return Text("Failed")
        case .cancelled: return Text("Cancelled")
        }
    }

    @ViewBuilder private var action: some View {
        switch download.state {
        case .downloading:
            IconButton(symbol: "xmark.circle.fill", label: "Cancel download", size: BrowserDesign.navigationButtonSize) { downloads.cancel(download) }
                .accessibilityIdentifier("downloads.cancel")
        case .finished:
            IconButton(symbol: "magnifyingglass", label: "Show in Finder", size: BrowserDesign.navigationButtonSize) {
                if let file = download.destination { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            }
            .accessibilityIdentifier("downloads.reveal")
        case .failed, .cancelled:
            IconButton(symbol: "arrow.clockwise", label: "Retry download", size: BrowserDesign.navigationButtonSize) { downloads.retry(download) }
                .accessibilityIdentifier("downloads.retry")
        }
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
