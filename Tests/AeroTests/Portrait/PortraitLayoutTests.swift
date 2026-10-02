@testable import Aero
import Foundation
import Testing

// docs/PORTRAIT.md › Layout. Written as failure modes first:
// 1. A chosen aspect is missed, or reached by cropping or shrinking the page instead of growing the backdrop.
// 2. The page leaves the canvas, or its margins are uneven when nothing asks for it.
// 3. The credit overlaps the page under a narrow margin, or takes room when it is hidden.
// 4. The title bar is not counted, so it pushes the page off the bottom.
// 5. A large full page renders past the pixel budget or the GPU's largest texture, or a small one below the display's density.
// 6. An unreadable saved style breaks the studio instead of falling back to the default.

struct PortraitLayoutTests {
    private let page = CGSize(width: 1200, height: 800)

    private func style(_ change: (inout PortraitStyle) -> Void) -> PortraitStyle {
        var style = PortraitStyle()
        change(&style)
        return style
    }

    @Test(arguments: PortraitStyle.Aspect.allCases)
    func everyAspectIsReachedByGrowingTheBackdrop(_ aspect: PortraitStyle.Aspect) {
        for page in [page, CGSize(width: 390, height: 2400), CGSize(width: 1600, height: 300)] {
            let layout = PortraitLayout(page: page, style: style { $0.aspect = aspect })
            if let ratio = aspect.ratio { #expect(abs(layout.canvas.width / layout.canvas.height - ratio) < 0.01) }
            #expect(layout.window.size == page, "The page keeps its size")
            #expect(layout.window.minX >= 0 && layout.window.minY >= 0)
            #expect(layout.window.maxX <= layout.canvas.width && layout.window.maxY <= layout.canvas.height)
        }
    }

    @Test func withoutCreditTheMarginsAreEven() {
        let layout = PortraitLayout(page: page, style: style { $0.showsCredit = false; $0.padding = 0.1 })
        let margin: CGFloat = 120
        #expect(layout.window == CGRect(x: margin, y: margin, width: page.width, height: page.height))
        #expect(layout.canvas == CGSize(width: page.width + 2 * margin, height: page.height + 2 * margin))
        #expect(layout.credit == nil)
    }

    @Test func theCreditAlwaysHasItsBandUnderThePage() {
        for padding in [0, 0.01, 0.08, 0.2] {
            let layout = PortraitLayout(page: page, style: style { $0.padding = padding })
            guard let credit = layout.credit else { Issue.record("No credit at padding \(padding)"); continue }
            #expect(layout.canvas.height - layout.window.maxY >= PortraitLayout.creditBand)
            #expect(credit.y > layout.window.maxY && credit.y < layout.canvas.height)
            #expect(credit.x == layout.canvas.width / 2)
        }
    }

    @Test func theTitleBarAddsToTheWindow() {
        let layout = PortraitLayout(page: page, style: style { $0.showsAddress = true; $0.aspect = .square })
        #expect(layout.window.height == page.height + PortraitLayout.titleBarHeight)
        #expect(layout.window.maxY <= layout.canvas.height - PortraitLayout.creditBand)
    }

    @Test func renderingStaysWithinThePixelBudget() {
        let small = PortraitLayout(page: page, style: PortraitStyle())
        #expect(small.scale(preferred: 2) == 2, "A window-sized portrait keeps the display's density")
        let tall = PortraitLayout(page: CGSize(width: 1440, height: PortraitShot.longestPage), style: PortraitStyle())
        let scale = tall.scale(preferred: 2)
        #expect(scale < 2)
        #expect(tall.canvas.width * tall.canvas.height * scale * scale <= PortraitLayout.maximumPixels * 1.001)
        #expect(max(tall.canvas.width, tall.canvas.height) * scale <= PortraitLayout.maximumSide)
    }

    @MainActor @Test func aSavedStyleComesBackAndAnUnreadableOneIsTheDefault() throws {
        let namespace = "portrait.\(UUID().uuidString)"
        defer { BrowserPreferences.erase(testNamespace: namespace) }
        BrowserPreferences(testNamespace: namespace).portraitStyle.backdrop = .aurora
        #expect(BrowserPreferences(testNamespace: namespace).portraitStyle.backdrop == .aurora)
        let suite = try #require(UserDefaults(suiteName: "app.getaero.browser.tests." + namespace))
        suite.set(Data("{".utf8), forKey: "browser.portrait.style")
        #expect(BrowserPreferences(testNamespace: namespace).portraitStyle == PortraitStyle())
    }
}
