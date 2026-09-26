import AppKit

/// Puts the chosen icon on the app bundle, as pasting one in the Finder's Get Info does, so the
/// Finder, the Dock, Launchpad and Spotlight show it even while Aero is closed. `nil` removes it,
/// back to the system icon, which follows the appearance.
@MainActor
enum AppIcon {
    /// macOS icon grid: the icon body is an 824 pt rounded square centred on a 1024 pt canvas.
    private static let canvas: CGFloat = 1024
    private static let body: CGFloat = 824
    private static let cornerRadius: CGFloat = 185.4
    private static let shadowBlur: CGFloat = 28
    private static let shadowOffset: CGFloat = -12
    private static let shadowOpacity: CGFloat = 0.28
    /// Where the Finder keeps a folder's or a bundle's custom icon.
    private static let customIconFile = "Icon\r"

    private static var bundlePath: String { Bundle.main.bundlePath }

    static func apply(_ variant: AppIconVariant?) {
        let image = variant.flatMap(image(for:))
        NSApp.applicationIconImage = image
        // Best effort: a bundle the person cannot write to keeps its icon outside the running Dock tile.
        _ = NSWorkspace.shared.setIcon(image, forFile: bundlePath)
        NSWorkspace.shared.noteFileSystemChanged(bundlePath)
    }

    /// At launch: the running Dock tile, and the bundle again when an update or a build replaced it.
    static func restore(_ variant: AppIconVariant?) {
        let isOnBundle = FileManager.default.fileExists(atPath: (bundlePath as NSString).appendingPathComponent(customIconFile))
        guard let variant else {
            if isOnBundle { apply(nil) }
            return
        }
        if isOnBundle { NSApp.applicationIconImage = image(for: variant) } else { apply(variant) }
    }

    /// The artwork masked and shadowed like a system icon, so it sits with the other icons.
    private static func image(for variant: AppIconVariant) -> NSImage? {
        guard let url = variant.artworkURL, let artwork = NSImage(contentsOf: url) else { return nil }
        let inset = (canvas - body) / 2
        let frame = NSRect(x: inset, y: inset, width: body, height: body)
        return NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
            let shape = NSBezierPath(roundedRect: frame, xRadius: cornerRadius, yRadius: cornerRadius)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = shadowBlur
            shadow.shadowOffset = NSSize(width: 0, height: shadowOffset)
            shadow.shadowColor = NSColor.black.withAlphaComponent(shadowOpacity)
            shadow.set()
            NSColor.black.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            shape.addClip()
            artwork.draw(in: frame)
            return true
        }
    }
}
