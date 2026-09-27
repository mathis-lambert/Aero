import SwiftUI

/// Each command renews the notice, even when zoom is already at its limit.
struct PageZoomFeedback: Identifiable {
    let id = UUID()
    let tabID: UUID
    let scale: Double
}

struct PageZoomIndicator: View {
    let feedback: PageZoomFeedback
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(feedback.scale, format: .percent.precision(.fractionLength(0)))
                .font(.body.weight(.medium).monospacedDigit())
                .contentTransition(.numericText(value: feedback.scale * 100))
                .browserAnimation(value: feedback.scale)
                .accessibilityLabel("Page zoom")
                .accessibilityValue(Text(feedback.scale, format: .percent.precision(.fractionLength(0))))
                .accessibilityIdentifier("page.zoom")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        .allowsHitTesting(false)
        .task(id: feedback.id) {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}
