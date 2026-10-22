import BrowserWebKit
import SwiftUI
import WebKit

struct BrowserContentView: View {
    let page: BrowserPage
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            // The page surface shows through until the document has painted, instead of a white flash.
            WebPageHost(page: page)
                .opacity(page.hasRenderedFirstFrame ? 1 : 0)
                .pageRevealAnimation(value: page.hasRenderedFirstFrame)
            if page.isLoading { PageProgress(page: page) }
            if let failure = page.failure {
                ContentUnavailableView {
                    Label(failure == .processTerminated ? "This page needs to be reloaded" : "This page could not be opened",
                          systemImage: "globe.badge.chevron.backward")
                } description: {
                    Text("Check the address or your connection, then try again.")
                } actions: {
                    Button("Try again") { page.reload() }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.canvas)
            }
        }
    }
}

/// The load's progress, in its own view: each step redraws the bar alone, not the page around it.
private struct PageProgress: View {
    let page: BrowserPage

    var body: some View {
        ProgressView(value: page.progress)
            .progressViewStyle(.linear)
            .frame(height: 2)
    }
}

/// Attaching a view never starts a navigation; the registry owns that lifecycle.
private struct WebPageHost: NSViewRepresentable {
    /// The container last given each page shows it. A page moves from a preview to its tab: the preview's container,
    /// still fading out, must never take its web view back.
    private static let owners = NSMapTable<BrowserPage, NSView>.weakToWeakObjects()

    let page: BrowserPage

    final class Coordinator {
        weak var page: BrowserPage?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        if context.coordinator.page !== page {
            context.coordinator.page = page
            Self.owners.setObject(container, forKey: page)
        }
        guard Self.owners.object(forKey: page) === container, page.webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        let webView = page.webView
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
