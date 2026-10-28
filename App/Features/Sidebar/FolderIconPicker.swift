import SwiftUI

/// The symbols a folder can take instead of its own, in a few families: work and study, making, leisure, life.
enum FolderSymbols {
    static let choices = [
        "briefcase", "building.2", "chart.bar", "doc.text", "newspaper", "graduationcap", "book", "brain",
        "chevron.left.forwardslash.chevron.right", "terminal", "cpu", "server.rack", "hammer", "wrench.and.screwdriver", "paintbrush", "paintpalette",
        "music.note", "headphones", "film", "tv", "gamecontroller", "camera", "photo", "sparkles",
        "house", "cart", "bag", "creditcard", "banknote", "airplane", "car", "map",
        "heart", "star", "bookmark", "flag", "leaf", "flame", "fork.knife", "figure.run",
    ]
}

/// A grid of symbols for a folder, the folder itself first; the one it has is ringed.
struct FolderIconPicker: View {
    private static let cell: CGFloat = 30
    private static let columns = 8

    let selected: String?
    let choose: (String?) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let grid = Array(repeating: GridItem(.fixed(Self.cell), spacing: 4), count: Self.columns)
        LazyVGrid(columns: grid, spacing: 4) {
            cell(nil) { FolderIcon(isOpen: false) }
                .accessibilityLabel(Text("Folder"))
            ForEach(FolderSymbols.choices, id: \.self) { symbol in
                // The system describes each symbol to VoiceOver, in the person's language.
                cell(symbol) { Image(systemName: symbol).font(.system(size: 13, weight: .medium)) }
            }
        }
        .padding(10)
        .accessibilityIdentifier("folderIconPicker")
    }

    private func cell(_ symbol: String?, @ViewBuilder icon: () -> some View) -> some View {
        let current = symbol == selected
        return Button { choose(symbol) } label: {
            icon()
                .foregroundStyle(current ? palette.ink : palette.secondary)
                .frame(width: Self.cell, height: Self.cell)
                .background(current ? palette.fill : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    if current { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle(radius: 7))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}
