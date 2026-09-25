import BrowserWebKit
import SwiftUI
import WebKit

struct BrowserContentView: View {
    let page: BrowserPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            // The page surface shows through until the document has painted, instead of a white flash.
            WebPageHost(page: page)
                .opacity(page.hasRenderedFirstFrame ? 1 : 0)
                .animation(reduceMotion ? nil : BrowserDesign.pageReveal, value: page.hasRenderedFirstFrame)
            if page.isLoading {
                ProgressView(value: page.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
            }
            if let failure = page.failure {
                VStack(spacing: 16) {
                    Image(systemName: "globe.badge.chevron.backward").font(.system(size: 36, weight: .light))
                    Text(failure == .processTerminated ? "This page needs to be reloaded" : "This page could not be opened")
                        .font(.title2)
                    Text("Check the address or your connection, then try again.")
                        .foregroundStyle(.secondary)
                    Button("Try again") { page.reload() }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
        }
    }
}

/// Attaching a view never starts a navigation; the registry owns that lifecycle.
private struct WebPageHost: NSViewRepresentable {
    let page: BrowserPage
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ container: NSView, context: Context) {
        guard page.webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        let webView = page.webView
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
