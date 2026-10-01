import AppKit
import BrowserWebKit
import UniformTypeIdentifiers

/// Opening files of this Mac in tabs, and saving pages to files, as Safari's File menu does. See docs/BROWSING.md ›
/// Files.
enum PageFileFormat {
    /// The page with its images and styles, which Safari and Aero open again.
    case webArchive
    case pdf

    var contentType: UTType {
        switch self {
        case .webArchive: .webArchive
        case .pdf: .pdf
        }
    }
}

extension BrowserModel {
    /// What a tab shows from this Mac: web pages, images, PDFs and text.
    static let openableFiles: [UTType] = [.html, .webArchive, .pdf, .image, .svg, .plainText, .xml]

    func chooseFileToOpen() {
        guard let window = WindowConfiguration.mainWindow else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.openableFiles
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            for file in panel.urls { self?.open(file) }
        }
    }

    func savePage(_ page: BrowserPage, as format: PageFileFormat) {
        guard let window = WindowConfiguration.mainWindow else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        let title = page.webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? page.webView.url?.siteName ?? String(localized: "Page")
        // A title may hold characters a file name cannot.
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.beginSheetModal(for: window) { [weak self, weak page] response in
            guard response == .OK, let file = panel.url, let page else { return }
            Task { @MainActor in
                do {
                    let data = switch format {
                    case .pdf: try await page.webView.pdf()
                    case .webArchive: try await withCheckedThrowingContinuation { continuation in
                        page.webView.createWebArchiveData { continuation.resume(with: $0) }
                    }
                    }
                    try data.write(to: file, options: .atomic)
                } catch {
                    self?.present(.error(String(localized: "The page could not be saved. Try again, or choose another folder.")))
                }
            }
        }
    }
}
