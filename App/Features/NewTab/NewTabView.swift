import SwiftUI

struct NewTabView: View {
    private static let fieldHeight: CGFloat = 52
    private static let submitSize: CGFloat = 30

    let browser: BrowserModel
    @State private var query = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack {
            Spacer(minLength: 32)
            HStack(spacing: BrowserDesign.fieldSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(BrowserDesign.Typography.fieldIcon)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search or enter an address", text: $query)
                    .textFieldStyle(.plain)
                    .font(BrowserDesign.Typography.field)
                    .focused($focused)
                    .onSubmit(submit)
                    .accessibilityIdentifier("newTab.input")
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(BrowserDesign.Typography.chrome.weight(.semibold))
                        .frame(width: Self.submitSize, height: Self.submitSize)
                        .background(query.isEmpty ? BrowserPalette(scheme: scheme).hover : BrowserPalette(scheme: scheme).pressed, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Open")
                .accessibilityIdentifier("newTab.submit")
            }
            .padding(.leading, 20)
            .padding(.trailing, (Self.fieldHeight - Self.submitSize) / 2)
            .frame(height: Self.fieldHeight)
            .browserSurface(fill: BrowserPalette(scheme: scheme).raised,
                            border: BrowserPalette(scheme: scheme).line,
                            radius: BrowserDesign.Radius.card)
            .paletteShadow()
            .frame(maxWidth: BrowserDesign.paletteWidth)
            .padding(.horizontal, 44)
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($focused, true)
        .task(id: browser.window.inputFocusRequest) {
            await Task.yield()
            focused = true
        }
    }

    private func submit() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        browser.submit(query, replacing: false)
    }
}
