import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist; only Aero reads it, other apps receive the tab's address.
    static let aeroTab = UTType(exportedAs: "app.getaero.browser.tab")
}

/// A tab being dragged within the sidebar.
struct TabDragItem: Codable, Transferable {
    let tabID: UUID
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .aeroTab)
        ProxyRepresentation(exporting: \.url)
    }
}
