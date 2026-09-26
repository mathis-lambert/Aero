import WebKit

/// State that would be lost or interrupted if the page were unloaded.
enum HibernationBlocker: Equatable {
    case capture, fullScreen, mediaPlayback, pictureInPicture, unsavedInput, unverifiedInput
}

extension BrowserPage {
    func hibernationBlocker() async -> HibernationBlocker? {
        if webView.cameraCaptureState != .none || webView.microphoneCaptureState != .none { return .capture }
        if webView.fullscreenState != .notInFullscreen { return .fullScreen }
        if await webView.requestMediaPlaybackState() == .playing { return .mediaPlayback }
        if webView.url == nil || failure == .processTerminated { return nil }
        do {
            // A paused video keeps its picture in picture window, which unloading the page would close.
            if try await webView.callAsyncJavaScript(PageScripts.isInPictureInPicture, contentWorld: PageScripts.world) as? Bool == true {
                return .pictureInPicture
            }
            let unsaved = try await webView.callAsyncJavaScript(PageScripts.hasUnsavedInput, contentWorld: PageScripts.world)
            return unsaved as? Bool == true ? .unsavedInput : nil
        } catch {
            // Keep the page when its input cannot be inspected; it is checked again later.
            return .unverifiedInput
        }
    }
}
