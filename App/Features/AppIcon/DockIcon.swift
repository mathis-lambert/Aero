import AppKit

/// Shows an alternate icon in the Dock. The Finder and Launchpad keep the bundle icon: a sandboxed app cannot
/// change its own bundle, so the choice applies while Aero runs.
@MainActor
enum DockIcon {
    /// macOS icon grid: the icon body is an 824 pt rounded square centred on a 1024 pt canvas.
    private static let canvas: CGFloat = 1024
    private static let body: CGFloat = 824
    private static let cornerRadius: CGFloat = 185.4
    private static let shadowBlur: CGFloat = 28
    private static let shadowOffset: CGFloat = -12
    private static let shadowOpacity: CGFloat = 0.28

    /// `nil` restores the bundle icon, which follows the light and dark appearance.
    static func apply(_ variant: AppIconVariant?) {
        NSApp.applicationIconImage = variant.flatMap(image(for:))
    }

    /// The artwork alone, for previews in Settings.
    static func artwork(for variant: AppIconVariant) -> NSImage? {
        guard let url = Bundle.main.url(forResource: variant.resourceName, withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// The artwork masked and shadowed like a system icon, so it sits with the other Dock icons.
    private static func image(for variant: AppIconVariant) -> NSImage? {
        guard let artwork = artwork(for: variant) else { return nil }
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
