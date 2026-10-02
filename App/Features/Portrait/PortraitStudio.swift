import AppKit
import BrowserCore
import BrowserWebKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// A picture of the page, with its size in points, and a small copy of it that previews draw.
struct PortraitShot: Sendable {
    /// The full page's tallest part, in points: a longer page is cut at its bottom.
    static let longestPage: CGFloat = 16_000
    /// The preview's longest side, in pixels: sharp in the studio, light enough to redraw as a slider moves.
    static let previewSide: CGFloat = 1600

    let image: CGImage
    let preview: CGImage
    let size: CGSize

    /// Pixels per point.
    var scale: CGFloat { size.width > 0 ? CGFloat(image.width) / size.width : 1 }

    nonisolated init(image: CGImage, size: CGSize) {
        self.image = image
        self.size = size
        preview = Self.downsampled(image, side: Self.previewSide) ?? image
    }

    /// What the page shows, as the tab is scrolled: what is on screen now, without waiting for the page to paint
    /// again, which a busy page may take long to do. The preview is drawn off the main actor.
    @MainActor static func visible(of webView: WKWebView) async throws -> PortraitShot {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        let snapshot = try await webView.takeSnapshot(configuration: configuration)
        guard let image = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw CocoaError(.featureUnsupported) }
        let size = snapshot.size
        return await Task.detached(priority: .userInitiated) { PortraitShot(image: image, size: size) }.value
    }

    /// The whole page, from WebKit's single-page PDF of it, drawn off the main actor.
    @MainActor static func fullPage(of webView: WKWebView, scale: CGFloat) async throws -> PortraitShot {
        let data = try await webView.pdf()
        return try await Task.detached(priority: .userInitiated) { try rasterize(data, scale: scale) }.value
    }

    nonisolated private static func rasterize(_ data: Data, scale: CGFloat) throws -> PortraitShot {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { throw CocoaError(.fileReadCorruptFile) }
        let box = page.getBoxRect(.mediaBox)
        let size = CGSize(width: box.width, height: min(box.height, longestPage))
        let scale = PortraitLayout.scale(of: size, preferred: scale)
        guard size.width >= 1, size.height >= 1, let context = bitmap(width: Int(size.width * scale), height: Int(size.height * scale)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        context.scaleBy(x: scale, y: scale)
        // Pages that paint no background are white in a browser.
        context.setFillColor(.white)
        context.fill(CGRect(origin: .zero, size: size))
        // PDF space rises from the bottom: the page's top lands at the context's top.
        context.translateBy(x: -box.minX, y: size.height - box.maxY)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
        return PortraitShot(image: image, size: size)
    }

    /// `nil` when `image` is already no larger.
    nonisolated static func downsampled(_ image: CGImage, side: CGFloat) -> CGImage? {
        let ratio = side / CGFloat(max(image.width, image.height))
        guard ratio < 1, let context = bitmap(width: Int(CGFloat(image.width) * ratio), height: Int(CGFloat(image.height) * ratio)) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage()
    }

    nonisolated private static func bitmap(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

/// How a portrait leaves Aero: JPEG, which keeps a window-sized picture under a megabyte, or PNG when it is
/// transparent. Encoding runs off the main actor.
enum PortraitEncoding {
    static let jpegQuality = 0.85
    /// The pasteboard's longest side, in pixels: sharp in any post or message, a fraction of a Retina full page.
    nonisolated static let copySide: CGFloat = 2560

    static func type(for style: PortraitStyle) -> UTType { style.backdrop == .clear ? .png : .jpeg }

    nonisolated static func data(_ image: CGImage, as type: UTType) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func encoded(_ image: CGImage, as type: UTType) async -> Data? {
        await Task.detached(priority: .userInitiated) { data(image, as: type) }.value
    }
}

/// The pasteboard's PNG, for apps that take no JPEG, such as web pages; encoded only when one pastes it.
private final class PortraitPasteboardData: NSObject, NSPasteboardItemDataProvider {
    let image: CGImage

    init(image: CGImage) { self.image = image }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let data = PortraitEncoding.data(image, as: .png) { item.setData(data, forType: type) }
    }
}

/// One capture being framed: the page's pictures, what the backdrops need, and the ways out, copy, save, share and
/// drag. The style lives in the preferences, so every capture starts from the last one's. See docs/PORTRAIT.md.
@MainActor @Observable
final class PortraitStudio: Identifiable {
    enum Failure {
        case fullPage, wallpaper, picture, save

        var message: String {
            switch self {
            case .fullPage: String(localized: "The full page could not be captured.")
            case .wallpaper: String(localized: "The desktop picture could not be read.")
            case .picture: String(localized: "The picture could not be made.")
            case .save: String(localized: "The picture could not be saved. Try again, or choose another folder.")
            }
        }
    }

    /// What a rendered picture depends on, so sharing after copying does not draw it again.
    private struct RenderKey: Equatable {
        let style: PortraitStyle
        let scheme: ColorScheme
        let fullPage: Bool
        let wallpaper: Bool
    }

    /// Wallpapers are drawn blurred or small: a 6K picture is decoded down to this.
    nonisolated private static let wallpaperPixels = 2400
    private static let files = FileManager.default.temporaryDirectory.appending(path: "Portraits", directoryHint: .isDirectory)
    /// The last copy's data, which the pasteboard asks for when an app pastes.
    private static var pasteboardData: PortraitPasteboardData?

    let id = UUID()
    let url: URL
    let title: String
    /// The page's theme color, else its favicon's, else the space's: the Site backdrop.
    let siteColor: Color
    /// `nil` while the snapshot is taken: the studio shows at once, at the page's size, and the picture follows.
    private(set) var visible: PortraitShot?
    /// The page's size as the capture began, which shapes the portrait until its picture arrives.
    let pageSize: CGSize
    /// What the frame shows until then: the page's own background.
    let placeholder: Color
    /// The window's pixels per point, which the snapshot will have.
    private let displayScale: CGFloat
    private(set) var fullPage: PortraitShot?
    private(set) var isLoadingFullPage = false
    /// `nil` until it is read, or when the desktop's picture cannot be.
    private(set) var wallpaper: CGImage?
    private(set) var copied = false
    private(set) var failure: Failure?
    private let preferences: BrowserPreferences
    @ObservationIgnored private weak var page: BrowserPage?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var fullPageTask: Task<Void, Never>?
    @ObservationIgnored private var wallpaperTask: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var rendered: (key: RenderKey, image: CGImage)?

    /// `failed` runs when the page cannot be pictured, and the studio is then of no use.
    init(page: BrowserPage, url: URL, title: String, siteColor: Color, preferences: BrowserPreferences, window: NSWindow?,
         failed: @escaping @MainActor (PortraitStudio) -> Void) {
        self.page = page
        self.url = url
        self.title = title
        self.siteColor = siteColor
        pageSize = page.webView.bounds.size
        placeholder = Color(nsColor: page.webView.underPageBackgroundColor)
        displayScale = page.webView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        self.preferences = preferences
        self.window = window
        captureTask = Task { [weak self, webView = page.webView] in
            do {
                let shot = try await PortraitShot.visible(of: webView)
                guard let self, !Task.isCancelled else { return }
                visible = shot
                prepare()
            } catch {
                guard let self, !Task.isCancelled else { return }
                failed(self)
            }
        }
        // Earlier studios' files, off the main actor: whatever received them has long read them.
        Task.detached(priority: .background) { [files = Self.files, current = id.uuidString] in
            let folders = (try? FileManager.default.contentsOfDirectory(at: files, includingPropertiesForKeys: nil)) ?? []
            for folder in folders where folder.lastPathComponent != current { try? FileManager.default.removeItem(at: folder) }
        }
        prepare()
    }

    isolated deinit {
        captureTask?.cancel()
        fullPageTask?.cancel()
        wallpaperTask?.cancel()
    }

    var style: PortraitStyle {
        get { preferences.portraitStyle }
        set {
            guard newValue != preferences.portraitStyle else { return }
            preferences.portraitStyle = newValue
            copied = false
            failure = nil
            prepare()
        }
    }

    /// The full page once it is drawn; the visible part until then; `nil` until the snapshot arrives.
    var shot: PortraitShot? { style.source == .fullPage ? fullPage ?? visible : visible }

    /// Whether there is a picture to copy, save, share or drag.
    var isReady: Bool { shot != nil && !isLoadingFullPage }

    var layout: PortraitLayout { PortraitLayout(page: shot?.size ?? pageSize, style: style) }

    /// The picture's size in pixels, as it will be exported.
    var pixelSize: CGSize {
        let layout = layout
        let scale = layout.scale(preferred: shot?.scale ?? displayScale)
        return CGSize(width: (layout.canvas.width * scale).rounded(), height: (layout.canvas.height * scale).rounded())
    }

    /// Starts what the style needs and does not have yet.
    private func prepare() {
        if style.source == .fullPage, visible != nil, fullPage == nil, fullPageTask == nil { loadFullPage() }
        if style.backdrop == .wallpaper, wallpaper == nil, wallpaperTask == nil { loadWallpaper() }
    }

    private func loadFullPage() {
        guard let page else { return fail(.fullPage) }
        isLoadingFullPage = true
        fullPageTask = Task { [weak self, webView = page.webView, scale = visible?.scale ?? displayScale] in
            let shot = try? await PortraitShot.fullPage(of: webView, scale: scale)
            guard let self, !Task.isCancelled else { return }
            isLoadingFullPage = false
            if let shot { fullPage = shot } else {
                fullPageTask = nil
                fail(.fullPage)
            }
        }
    }

    /// The desktop picture of the window's screen, decoded off the main actor.
    private func loadWallpaper() {
        guard let screen = window?.screen ?? NSScreen.main, let file = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return fail(.wallpaper)
        }
        wallpaperTask = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.wallpaperPixels,
                ] as CFDictionary)
            }.value
            guard let self, !Task.isCancelled else { return }
            if let image { wallpaper = image } else {
                wallpaperTask = nil
                fail(.wallpaper)
            }
        }
    }

    /// Returns to what works, and says why.
    private func fail(_ failure: Failure) {
        var style = style
        switch failure {
        case .fullPage: style.source = .visible
        case .wallpaper: style.backdrop = .gradient
        case .picture, .save: break
        }
        preferences.portraitStyle = style
        self.failure = failure
    }

    // MARK: - The picture

    /// The portrait at `zoom` times its size: previews draw the small copy of the page, exports the page itself.
    func canvas(in scheme: ColorScheme, zoom: CGFloat = 1) -> PortraitCanvas {
        PortraitCanvas(shot: shot, placeholder: placeholder, style: style, layout: layout, zoom: zoom, url: url, wallpaper: wallpaper,
                       siteColor: siteColor, scheme: scheme)
    }

    /// The portrait at the page's own pixel density, within the layout's limits; kept until the style changes.
    func render(in scheme: ColorScheme) -> CGImage? {
        let key = RenderKey(style: style, scheme: scheme, fullPage: style.source == .fullPage && fullPage != nil, wallpaper: wallpaper != nil)
        if let rendered, rendered.key == key { return rendered.image }
        guard let shot, !isLoadingFullPage else { return nil }
        let layout = layout
        let renderer = ImageRenderer(content: canvas(in: scheme))
        renderer.proposedSize = ProposedViewSize(layout.canvas)
        renderer.scale = layout.scale(preferred: shot.scale)
        renderer.isOpaque = style.backdrop != .clear
        guard let image = renderer.cgImage else { return nil }
        rendered = (key, image)
        return image
    }

    /// The site and the moment, as Screenshot names its files.
    private var fileName: String {
        BrowserModel.fileName(from: "\(url.siteName) \(Date.now.formatted(date: .numeric, time: .shortened))")
    }

    /// The pasteboard's picture, at most `PortraitEncoding.copySide` on its longest side: JPEG first, which apps that
    /// take it prefer, and a promised PNG for the others. A transparent picture is PNG only.
    func copy(in scheme: ColorScheme) async -> Bool {
        guard let image = render(in: scheme) else {
            failure = .picture
            return false
        }
        let transparent = style.backdrop == .clear
        let (copy, jpeg) = await Task.detached(priority: .userInitiated) { () -> (CGImage, Data?) in
            let copy = PortraitShot.downsampled(image, side: PortraitEncoding.copySide) ?? image
            return (copy, transparent ? nil : PortraitEncoding.data(copy, as: .jpeg))
        }.value
        let png = PortraitPasteboardData(image: copy)
        let item = NSPasteboardItem()
        if let jpeg { item.setData(jpeg, forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)) }
        item.setDataProvider(png, forTypes: [.png])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        Self.pasteboardData = png
        copied = true
        return true
    }

    /// Asks where, then writes the picture; `saved` runs once it is written.
    func save(in scheme: ColorScheme, saved: @escaping @MainActor () -> Void) {
        guard let window else { return }
        let type = PortraitEncoding.type(for: style)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = fileName
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let file = panel.url, let self else { return }
            Task {
                guard let image = self.render(in: scheme), let data = await PortraitEncoding.encoded(image, as: type) else {
                    self.failure = .picture
                    return
                }
                do {
                    try await Task.detached(priority: .userInitiated) { try data.write(to: file, options: .atomic) }.value
                    saved()
                } catch {
                    self.failure = .save
                }
            }
        }
    }

    /// The picture as a file, for sharing and dragging, which take files with their names.
    func file(in scheme: ColorScheme) async -> URL? {
        let type = PortraitEncoding.type(for: style)
        let folder = Self.files.appending(path: id.uuidString, directoryHint: .isDirectory)
        let file = folder.appending(path: fileName).appendingPathExtension(for: type)
        guard let image = render(in: scheme), let data = await PortraitEncoding.encoded(image, as: type) else {
            failure = .picture
            return nil
        }
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            }.value
            return file
        } catch {
            failure = .picture
            return nil
        }
    }

    func share(in scheme: ColorScheme, from anchor: NSView) {
        Task {
            guard let file = await file(in: scheme) else { return }
            NSSharingServicePicker(items: [file]).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    /// The picture for a drag, made once it is dropped rather than as the drag begins.
    func dragItem(in scheme: ColorScheme) -> NSItemProvider {
        let type = PortraitEncoding.type(for: style)
        let provider = NSItemProvider()
        provider.suggestedName = fileName
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { [weak self] completion in
            Task { @MainActor in
                let file = await self?.file(in: scheme)
                completion(file, false, file == nil ? CocoaError(.fileWriteUnknown) : nil)
            }
            return nil
        }
        return provider
    }
}

extension BrowserModel {
    /// Opens the quick popover on the selected page at once; the studio pictures the page meanwhile. A change of tab
    /// or space closes the popover, which drops a snapshot still on its way.
    func capturePortrait() {
        guard let page = currentPage, let tab = selectedTab, window.prompt == nil else { return }
        window.controlCenterPresented = false
        window.controlBar = nil
        window.portrait = PortraitStudio(page: page, url: page.webView.url ?? tab.url, title: tab.displayTitle, siteColor: siteColor(of: page, tab: tab),
                                         preferences: preferences, window: WindowConfiguration.mainWindow) { [weak self] studio in
            guard let self, window.portrait === studio else { return }
            window.portrait = nil
            present(.error(String(localized: "The page could not be captured. Try again once it has loaded.")))
        }
    }

    private func siteColor(of page: BrowserPage, tab: BrowserTab) -> Color {
        if let theme = page.webView.themeColor { return Color(nsColor: theme) }
        if let color = faviconKey(for: tab).flatMap({ favicons.favicon(for: $0).color }) { return Color(nsColor: color) }
        return accent.tint
    }
}
