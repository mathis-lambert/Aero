import SwiftUI

extension View {
    /// Menu items showing their symbol before their title, as the system's own menus do, in the menu's own ink rather
    /// than the space's color the window tints its controls with; a SwiftUI menu on the Mac shows titles alone
    /// otherwise. Every item gives a symbol.
    func menuIcons() -> some View {
        labelStyle(.titleAndIcon).tint(nil)
    }

    /// A context menu whose items show their symbols (`menuIcons`).
    func iconContextMenu(@ViewBuilder _ items: () -> some View) -> some View {
        contextMenu { items().menuIcons() }
    }
}
