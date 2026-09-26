import AppKit

/// Puts the chosen icon on the app bundle, as pasting one in the Finder's Get Info does, so the
/// Finder, the Dock, Launchpad and Spotlight show it even while Aero is closed.
/// Automatic leaves the bundle artwork intact and follows the app appearance in the running Dock.
@MainActor
final class AppIcon {
    private var variant: AppIconVariant?
    private var appearanceObservation: NSKeyValueObservation?
    private var renderedVariant: AppIconVariant?

    init(variant: AppIconVariant?) {
        self.variant = variant
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateRunningIcon() }
        }
    }

    private func updateRunningIcon() {
        let resolved = variant ?? .system(dark: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        guard renderedVariant != resolved, let image = Self.image(for: resolved) else { return }
        NSApp.applicationIconImage = image
        renderedVariant = resolved
    }

    /// macOS icon grid: the icon body is an 824 pt rounded square centred on a 1024 pt canvas.
    private static let canvas: CGFloat = 1024
    private static let body: CGFloat = 824
    private static let cornerRadius: CGFloat = 185.4
    private static let shadowBlur: CGFloat = 28
    private static let shadowOffset: CGFloat = -12
    private static let shadowOpacity: CGFloat = 0.28

    private static var bundlePath: String { Bundle.main.bundlePath }

    func apply(_ variant: AppIconVariant?) {
        self.variant = variant
        // Best effort: a read-only bundle keeps its original icon outside the running Dock tile.
        _ = NSWorkspace.shared.setIcon(variant.flatMap(Self.image(for:)), forFile: Self.bundlePath)
        renderedVariant = nil
        updateRunningIcon()
    }

    /// The artwork masked and shadowed like a system icon, so it sits with the other icons.
    private static func image(for variant: AppIconVariant) -> NSImage? {
        guard let artwork = variant.artwork else { return nil }
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
