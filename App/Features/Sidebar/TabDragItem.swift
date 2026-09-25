import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist; only Auro reads it, other apps receive the tab's address.
    static let auroTab = UTType(exportedAs: "dev.auro.tab")
}

/// A tab being dragged within the sidebar.
struct TabDragItem: Codable, Transferable {
    let tabID: UUID
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .auroTab)
        ProxyRepresentation(exporting: \.url)
    }
}
