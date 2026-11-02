import AppKit
import BrowserWebKit
import Observation
import WebKit

/// Best-effort pictures of pages already shown, never a reason to load, resize or keep a page alive.
@MainActor @Observable
final class TabPreviews {
    private struct Preview {
        let url: URL
        let image: CGImage
        var bytes: Int { image.bytesPerRow * image.height }
    }

    private var previews: [UUID: Preview] = [:]
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private var pending: (token: UUID, tabID: UUID)?
    @ObservationIgnored private var timeout: Task<Void, Never>?

    isolated deinit { timeout?.cancel() }

    func image(for id: UUID, at url: URL) -> CGImage? {
        guard previews[id]?.url == url else { return nil }
        return previews[id]?.image
    }

    func remove(_ id: UUID) {
        previews[id] = nil
        order.removeAll { $0 == id }
        if pending?.tabID == id { timeout?.cancel(); timeout = nil; pending = nil }
    }

    func keep(only ids: Set<UUID>) {
        for id in order where !ids.contains(id) { remove(id) }
        if let id = pending?.tabID, !ids.contains(id) { remove(id) }
    }

    func capture(_ id: UUID, page: BrowserPage, refresh: Bool, isCurrent: @escaping @MainActor () -> Bool) {
        let view = page.webView
        guard pending == nil, let url = page.url, !page.isLoading, page.failure == nil,
              page.hasRenderedFirstFrame, view.window != nil, !view.isHiddenOrHasHiddenAncestor,
              view.bounds.width > 0, view.bounds.height > 0,
              refresh || image(for: id, at: url) == nil else { return }
        let token = UUID()
        pending = (token, id)
        // A slow/failed snapshot never blocks another page's preview or the tab switch itself.
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, pending?.token == token else { return }
            pending = nil
            timeout = nil
        }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        configuration.snapshotWidth = 200
        configuration.rect = CGRect(x: view.bounds.minX, y: view.bounds.minY, width: view.bounds.width,
                                    height: min(view.bounds.height, view.bounds.width / 1.6))
        view.takeSnapshot(with: configuration) { [weak self, weak page] snapshot, error in
            guard let self, pending?.token == token else { return }
            timeout?.cancel(); timeout = nil; pending = nil
            // Snapshots are optional decoration. Failures keep the previous picture or the site's placeholder.
            guard error == nil, let page, page.url == url, !page.isLoading, isCurrent(),
                  let image = snapshot?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  image.width <= 800, image.height <= 500 else { return }
            previews[id] = Preview(url: url, image: image)
            order.removeAll { $0 == id }
            order.append(id)
            while order.count > 8 || previews.values.reduce(0, { $0 + $1.bytes }) > 8 * 1024 * 1024 {
                guard let oldest = order.first else { break }
                remove(oldest)
            }
        }
    }
}

extension BrowserModel {
    func captureTabPreview(_ id: UUID, refresh: Bool = false) {
        guard let page = pages.livePage(id) else { return }
        tabPreviews.capture(id, page: page, refresh: refresh) { [weak self, weak page] in
            guard let self, let page else { return false }
            return pages.livePage(id) === page && session.tabs.contains { $0.id == id && $0.url == page.url }
        }
    }
}
