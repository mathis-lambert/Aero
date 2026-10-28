import AppKit
import BrowserWebKit
import SwiftUI

/// A download in the popover: its file, name and progress, with the speed and time left while it comes, and the
/// action its state calls for. A finished file drags out to the Finder or another app; the menu renames it or moves
/// it to the Trash.
struct DownloadRow: View {
    let download: BrowserDownload
    let downloads: DownloadCoordinator
    @Binding var renaming: BrowserDownload.ID?
    /// What went wrong with the last rename or move to the Trash, shown in place of the status.
    @State private var problem: LocalizedStringKey?

    var body: some View {
        HStack(spacing: BrowserDesign.rowInset) {
            FileIcon(filename: download.filename)
                .opacity(download.state == .finished ? 1 : 0.6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if renaming == download.id {
                    RenameField(name: download.filename, isFilename: true) { rename(to: $0) } end: { renaming = nil }
                } else {
                    Text(verbatim: download.filename).lineLimit(1).truncationMode(.middle)
                }
                if download.state == .downloading || download.state == .paused, download.totalBytes != nil {
                    ProgressView(value: download.fractionCompleted)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .tint(download.state == .paused ? .secondary : nil)
                }
                Group { if let problem { Text(problem) } else { status } }
                    .font(BrowserDesign.Typography.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(.horizontal, BrowserDesign.rowInset)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open() }
        .modifier(FileDrag(file: download.state == .finished ? download.destination : nil, filename: download.filename))
        .iconContextMenu { menu }
        .onChange(of: renaming) { if renaming == download.id { problem = nil } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloads.row")
    }

    private var status: Text {
        let completed = download.completedBytes.formatted(.byteCount(style: .file))
        let total = download.totalBytes?.formatted(.byteCount(style: .file))
        switch download.state {
        case .downloading:
            let rate = download.bytesPerSecond.map { Int64($0).formatted(.byteCount(style: .file)) }
            switch (total, rate, download.remainingTime) {
            case let (total?, rate?, remaining?):
                let left = remaining.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
                return Text("\(completed) of \(total) · \(rate)/s · \(left) left")
            case let (total?, _, _): return Text("\(completed) of \(total)")
            case let (nil, rate?, _): return Text("\(completed) · \(rate)/s")
            case (nil, nil, _): return Text(verbatim: completed)
            }
        case .paused:
            if let total { return Text("Paused · \(completed) of \(total)") }
            return Text("Paused · \(completed)")
        case .finished: return Text(verbatim: completed)
        case .failed: return Text("Failed")
        case .cancelled: return Text("Cancelled")
        }
    }

    @ViewBuilder private var actions: some View {
        switch download.state {
        case .downloading:
            IconButton(symbol: "pause.circle.fill", label: "Pause download", size: BrowserDesign.navigationButtonSize) { downloads.pause(download) }
                .accessibilityIdentifier("downloads.pause")
            cancelButton
        case .paused:
            IconButton(symbol: "play.circle.fill", label: "Resume download", size: BrowserDesign.navigationButtonSize) { downloads.resume(download) }
                .accessibilityIdentifier("downloads.resume")
            cancelButton
        case .finished:
            IconButton(symbol: "magnifyingglass", label: "Show in Finder", size: BrowserDesign.navigationButtonSize) { reveal() }
                .accessibilityIdentifier("downloads.reveal")
        case .failed, .cancelled:
            IconButton(symbol: "arrow.clockwise", label: "Retry download", size: BrowserDesign.navigationButtonSize) { downloads.retry(download) }
                .accessibilityIdentifier("downloads.retry")
        }
    }

    private var cancelButton: some View {
        IconButton(symbol: "xmark.circle.fill", label: "Cancel download", size: BrowserDesign.navigationButtonSize) { downloads.cancel(download) }
            .accessibilityIdentifier("downloads.cancel")
    }

    @ViewBuilder private var menu: some View {
        switch download.state {
        case .downloading:
            Button("Pause", systemImage: "pause") { downloads.pause(download) }
            Button("Cancel", systemImage: "xmark") { downloads.cancel(download) }
        case .paused:
            Button("Resume", systemImage: "play") { downloads.resume(download) }
            Button("Cancel", systemImage: "xmark") { downloads.cancel(download) }
        case .finished:
            Button("Open", systemImage: "arrow.up.forward.app") { open() }
            Button("Show in Finder", systemImage: "magnifyingglass") { reveal() }
            Button("Rename…", systemImage: "pencil") { renaming = download.id }
        case .failed, .cancelled:
            Button("Retry", systemImage: "arrow.clockwise") { downloads.retry(download) }
        }
        if let source = download.sourceURL {
            Button("Copy Download Address", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([source as NSURL])
            }
        }
        if download.state != .downloading, download.state != .paused {
            Divider()
            Button("Remove from List", systemImage: "minus.circle") { downloads.remove(download) }
        }
        if download.state == .finished {
            Button("Move to Trash", systemImage: "trash", role: .destructive) { moveToTrash() }
        }
    }

    private func open() {
        if download.state == .finished, let file = download.destination { NSWorkspace.shared.open(file) }
    }

    private func reveal() {
        if let file = download.destination { NSWorkspace.shared.activateFileViewerSelecting([file]) }
    }

    private func rename(to name: String) {
        do {
            try downloads.rename(download, to: name)
        } catch {
            switch error {
            case .nameTaken: problem = "Another file in Downloads has that name."
            case .invalidName: problem = "That name can’t be used."
            case .fileMissing: problem = "The file was moved or deleted."
            case .notRenamed: problem = "The file couldn’t be renamed."
            }
        }
    }

    private func moveToTrash() {
        do {
            try downloads.moveToTrash(download)
        } catch {
            problem = "The file couldn’t be moved to the Trash."
        }
    }
}

/// Lets a finished file be dragged out as the file itself, as from the Finder.
private struct FileDrag: ViewModifier {
    let file: URL?
    let filename: String

    func body(content: Content) -> some View {
        if let file {
            content.onDrag { NSItemProvider(contentsOf: file) ?? NSItemProvider() } preview: { FileIcon(filename: filename) }
        } else {
            content
        }
    }
}
