import SwiftUI

/// Chooses how much of a profile's history to clear, like Safari's Clear History sheet.
struct ClearHistorySheet: View {
    let profileName: String
    let clear: (HistoryClearRange) -> Void
    @State private var range = HistoryClearRange.lastHour
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clear history for “\(profileName)”?").font(.headline)
            Text("Visited pages are removed from this profile’s history. Tabs, website data and sign-ins are kept.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Clear", selection: $range) {
                ForEach(HistoryClearRange.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("history.clearRange")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clear history", role: .destructive) {
                    clear(range)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("history.confirmClear")
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
