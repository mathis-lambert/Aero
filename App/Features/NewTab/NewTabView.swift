import SwiftUI

struct NewTabView: View {
    let browser: BrowserModel
    @State private var query = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack {
            Spacer(minLength: 32)
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search or enter an address", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit(submit)
                    .accessibilityIdentifier("newTab.input")
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(.primary.opacity(query.isEmpty ? 0.035 : 0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Open")
                .accessibilityIdentifier("newTab.submit")
            }
            .padding(.horizontal, 20)
            .frame(height: 70)
            .browserSurface(fill: BrowserPalette(scheme: scheme).raised,
                            border: BrowserPalette(scheme: scheme).line,
                            radius: BrowserDesign.Radius.card)
            .frame(maxWidth: 600)
            .padding(.horizontal, 44)
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($focused, true)
        .task(id: browser.window.newTabFocusID) {
            await Task.yield()
            focused = true
        }
    }

    private func submit() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        browser.submit(query, replacing: false)
    }
}
