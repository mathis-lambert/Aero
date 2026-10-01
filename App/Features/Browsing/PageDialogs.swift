import BrowserWebKit
import SwiftUI

/// A page's `alert`, `confirm` or `prompt` waiting for its answer, which is given once.
@MainActor
final class PageDialogRequest: Identifiable {
    let id = UUID()
    /// The tab that asks; `nil` for a popup window's page, which asks over its own window.
    let tabID: UUID?
    let dialog: PageDialog
    private var respond: ((PageDialogAnswer) -> Void)?

    init(tabID: UUID?, dialog: PageDialog, respond: @escaping (PageDialogAnswer) -> Void) {
        self.tabID = tabID
        self.dialog = dialog
        self.respond = respond
    }

    func answer(_ answer: PageDialogAnswer) {
        respond?(answer)
        respond = nil
    }
}

extension BrowserModel {
    /// Asked in the window once its tab is shown and no other question is, as Safari does for a background tab. A
    /// tab closed meanwhile answers as dismissed. See docs/BROWSING.md › Page dialogs.
    func page(_ tabID: UUID, presents dialog: PageDialog) async -> PageDialogAnswer {
        while window.selectedTabID != tabID || window.prompt != nil || isChangingStructure {
            guard session.tabs.contains(where: { $0.id == tabID }) else { return .dismissed }
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = window.selectedTabID
                    _ = window.prompt
                    _ = session.tabs.count
                    _ = isChangingStructure
                } onChange: { continuation.resume() }
            }
        }
        return await withCheckedContinuation { continuation in
            present(.pageDialog(PageDialogRequest(tabID: tabID, dialog: dialog) { continuation.resume(returning: $0) }))
        }
    }

    func answer(_ request: PageDialogRequest, _ answer: PageDialogAnswer) {
        if case .pageDialog(let shown) = window.prompt, shown === request { window.prompt = nil }
        request.answer(answer)
    }
}

/// A page's dialog as the shared prompt, in the browser window or a popup window.
struct PageDialogCard: View {
    let dialog: PageDialog
    let answer: (PageDialogAnswer) -> Void
    @State private var text = ""
    @State private var suppressesMore = false

    var body: some View {
        Prompt(title: Text("\(dialog.site) says"), message: Text(verbatim: dialog.message)) {
            if case .prompt = dialog.kind {
                TextField("Answer", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .accessibilityIdentifier("pageDialog.text")
            }
            if dialog.offersSuppression {
                Toggle("Don’t allow more dialogs from this page", isOn: $suppressesMore)
                    .accessibilityIdentifier("pageDialog.suppress")
            }
        } actions: {
            if dialog.kind != .alert {
                PromptCancelButton { answer(PageDialogAnswer(accepted: false, suppressesMore: suppressesMore)) }
            }
            PromptConfirmButton(title: "OK") { answer(PageDialogAnswer(accepted: true, text: text, suppressesMore: suppressesMore)) }
                .accessibilityIdentifier("pageDialog.ok")
        }
        .accessibilityIdentifier("pageDialog.prompt")
        .onAppear { if case .prompt(let defaultText) = dialog.kind { text = defaultText } }
    }
}
