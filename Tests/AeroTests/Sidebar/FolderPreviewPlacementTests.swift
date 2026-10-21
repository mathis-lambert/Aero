@testable import Aero
import CoreGraphics
import Testing

// docs/BROWSING.md › Favorites and open tabs. Written as failure modes first:
// 1. The preview covers the header, or opens on its leading side with room on its trailing one.
// 2. A sidebar near the screen's edge pushes the preview off screen instead of flipping it.
// 3. Right to left, it opens over the sidebar instead of beside it.
// 4. A header near the bottom of the screen hangs the preview below it.

struct FolderPreviewPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 248, height: 200)
    private let gap = FolderPreviewPlacement.gap

    @Test func itOpensBesideTheHeaderWithItsTopLevel() {
        let header = CGRect(x: 10, y: 600, width: 180, height: 34)
        let origin = FolderPreviewPlacement.origin(beside: header, size: size, screen: screen, rightToLeft: false)
        #expect(origin == CGPoint(x: header.maxX + gap, y: header.maxY - size.height))
    }

    @Test func itFlipsWhenTheTrailingSideHasNoRoom() {
        let header = CGRect(x: 1260, y: 600, width: 170, height: 34)
        let origin = FolderPreviewPlacement.origin(beside: header, size: size, screen: screen, rightToLeft: false)
        #expect(origin.x == header.minX - gap - size.width)
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 900)
        let squeezed = FolderPreviewPlacement.origin(beside: CGRect(x: 40, y: 600, width: 200, height: 34), size: size, screen: narrow, rightToLeft: false)
        #expect(squeezed.x >= narrow.minX && squeezed.x + size.width <= narrow.maxX, "With room on neither side, it stays on screen")
    }

    @Test func rightToLeftItOpensOnTheLeft() {
        let header = CGRect(x: 1250, y: 600, width: 180, height: 34)
        let origin = FolderPreviewPlacement.origin(beside: header, size: size, screen: screen, rightToLeft: true)
        #expect(origin.x == header.minX - gap - size.width)
    }

    @Test func itStaysOnScreenVertically() {
        let low = CGRect(x: 10, y: 20, width: 180, height: 34)
        #expect(FolderPreviewPlacement.origin(beside: low, size: size, screen: screen, rightToLeft: false).y == screen.minY)
        let high = CGRect(x: 10, y: 1000, width: 180, height: 34)
        #expect(FolderPreviewPlacement.origin(beside: high, size: size, screen: screen, rightToLeft: false).y == screen.maxY - size.height)
    }
}
