import AppKit
import WebKit

extension BrowserPage {
    // Familiar browser steps; each command changes the page once, with no timer or observation.
    private static let zoomLevels: [Double] = [0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5]

    public var zoom: Double { webView.pageZoom }

    public func changeZoom(increasing: Bool) {
        let current = webView.pageZoom
        let next = increasing ? Self.zoomLevels.first { $0 > current + 0.001 }
            : Self.zoomLevels.last { $0 < current - 0.001 }
        if let next { webView.pageZoom = next }
    }

    public func resetZoom() { webView.pageZoom = 1 }

    public func reloadFromOrigin() {
        if webView.url != nil { webView.reloadFromOrigin() }
        else { reload() }
    }

    public func printPage() {
        guard let window = webView.window else { return }
        let operation = webView.printOperation(with: NSPrintInfo.shared)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
