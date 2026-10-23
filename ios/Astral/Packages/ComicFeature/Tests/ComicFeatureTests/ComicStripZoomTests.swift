import Testing
import SwiftUI
@testable import ComicFeature

@Suite("ComicStripZoom")
struct ComicStripZoomTests {

    @Test("first pinch zooms around the fingers and clamps the scale")
    func firstPinchUsesFingerAnchor() {
        var zoom = ComicStripZoom()
        zoom.pinch(magnification: 2, startAnchor: UnitPoint(x: 0.2, y: 0.7))
        #expect(zoom.scale == 2)
        #expect(zoom.anchor == UnitPoint(x: 0.2, y: 0.7))
        zoom.pinch(magnification: 10, startAnchor: .zero)
        #expect(zoom.scale == ComicStripZoom.maxScale)
    }

    @Test("a second pinch keeps the current framing")
    func secondPinchKeepsAnchor() {
        var zoom = ComicStripZoom()
        zoom.pinch(magnification: 2, startAnchor: UnitPoint(x: 0.3, y: 0.4))
        zoom.endPinch()
        zoom.pinch(magnification: 1.5, startAnchor: UnitPoint(x: 0.9, y: 0.9))
        #expect(zoom.scale == 3)
        #expect(zoom.anchor == UnitPoint(x: 0.3, y: 0.4))
    }

    @Test("a nearly closed pinch snaps back to fit")
    func smallPinchSnapsBack() {
        var zoom = ComicStripZoom()
        zoom.pinch(magnification: 1.05, startAnchor: .center)
        zoom.endPinch()
        #expect(zoom.scale == 1)
        #expect(!zoom.isZoomed)
    }

    @Test("panning moves the visible area with the finger and stops at the edges")
    func panFollowsFingerWithinEdges() {
        var zoom = ComicStripZoom()
        zoom.pinch(magnification: 2, startAnchor: .center)
        zoom.endPinch()
        // At 2x on a 400 pt wide strip, 100 pt of finger travel is a quarter of the pan range.
        zoom.pan(translationX: 100, width: 400)
        #expect(abs(zoom.anchor.x - 0.25) < 0.0001)
        zoom.pan(translationX: 1000, width: 400)
        #expect(zoom.anchor.x == 0)
        zoom.endPan()
        zoom.pan(translationX: -1000, width: 400)
        #expect(zoom.anchor.x == 1)
    }

    @Test("panning does nothing while the strip fits the screen")
    func panIgnoredWhenNotZoomed() {
        var zoom = ComicStripZoom()
        zoom.pan(translationX: 200, width: 400)
        #expect(zoom.anchor == .center)
    }

    @Test("double tap zooms in at the tap and back out")
    func doubleTapToggles() {
        var zoom = ComicStripZoom()
        zoom.toggle(at: CGPoint(x: 300, y: 200), in: CGSize(width: 400, height: 800))
        #expect(zoom.scale == ComicStripZoom.doubleTapScale)
        #expect(zoom.anchor == UnitPoint(x: 0.75, y: 0.25))
        zoom.toggle(at: .zero, in: CGSize(width: 400, height: 800))
        #expect(zoom.scale == 1)
    }
}
