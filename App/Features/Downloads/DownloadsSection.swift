import AppKit
import BrowserWebKit
import SwiftUI
import UniformTypeIdentifiers

/// Shown at the bottom of the sidebar only while the session has downloads.
struct DownloadsSection: View {
    private static let maximumVisibleRows: CGFloat = 3
    private static let rowHeight: CGFloat = 44

    let downloads: DownloadCoordinator
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Downloads").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if downloads.downloads.contains(where: { $0.state != .downloading }) {
                    Button("Clear") { downloads.clearInactive() }
                        .buttonStyle(.plain)
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("downloads.clear")
                }
            }
            .padding(.horizontal, 10)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(downloads.downloads) { download in
                        DownloadRow(download: download, downloads: downloads)
                            .frame(height: Self.rowHeight)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(maxHeight: Self.rowHeight * Self.maximumVisibleRows)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(BrowserPalette(scheme: scheme).line).frame(height: 1).padding(.horizontal, 14)
        }
    }
}

private struct DownloadRow: View {
    let download: BrowserDownload
    let downloads: DownloadCoordinator

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(filename: download.filename)
                .opacity(download.state == .downloading ? 0.6 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: download.filename).lineLimit(1).truncationMode(.middle)
                if download.state == .downloading, download.totalBytes != nil {
                    ProgressView(value: download.fractionCompleted).progressViewStyle(.linear).controlSize(.mini)
                }
                status.font(.caption2).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: 0)
            action
        }
        .padding(.horizontal, 10)
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

/// Its own view, so progress updates of the row do not ask the system for the icon again.
private struct FileIcon: View {
    let filename: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data))
            .resizable()
            .frame(width: BrowserDesign.downloadIconSize, height: BrowserDesign.downloadIconSize)
    }
}
