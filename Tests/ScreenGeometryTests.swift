import CoreGraphics
import Testing

@testable import ParketCore

@Suite("Screen geometry")
struct ScreenGeometryTests {
    @Test func conversionUsesPrimaryScreenTopEdge() {
        let screens = [
            ScreenDescriptor(
                displayID: 2,
                frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1410),
                scale: 1
            ),
            ScreenDescriptor(
                displayID: 1,
                frame: CGRect(x: 413, y: -982, width: 1512, height: 982),
                visibleFrame: CGRect(x: 413, y: -982, width: 1512, height: 950),
                scale: 2
            ),
        ]

        let external = ScreenGeometry.convertRect(screens[0].frame, screens: screens)
        let builtin = ScreenGeometry.convertRect(screens[1].frame, screens: screens)
        let builtinVisible = ScreenGeometry.convertRect(screens[1].visibleFrame, screens: screens)

        #expect(external == CGRect(x: 0, y: 0, width: 2560, height: 1440))
        #expect(builtin == CGRect(x: 413, y: 1440, width: 1512, height: 982))
        #expect(builtinVisible == CGRect(x: 413, y: 1472, width: 1512, height: 950))
    }

    @Test func displayAbovePrimaryKeepsNegativeAXCoordinates() {
        let snapshot = ScreenSnapshot([
            ScreenDescriptor(
                displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
                scale: 2
            ),
            ScreenDescriptor(
                displayID: 2,
                frame: CGRect(x: 0, y: 1080, width: 1920, height: 1200),
                visibleFrame: CGRect(x: 0, y: 1080, width: 1920, height: 1175),
                scale: 1
            ),
        ])

        #expect(snapshot.screen(displayID: 1)?.frame == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(snapshot.screen(displayID: 2)?.frame == CGRect(x: 0, y: -1200, width: 1920, height: 1200))
        #expect(snapshot.screen(displayID: 2)?.visibleFrame == CGRect(x: 0, y: -1175, width: 1920, height: 1175))
    }

    @Test func snapshotKeepsConvertedFramesTogether() {
        let snapshot = ScreenSnapshot([
            ScreenDescriptor(
                displayID: 2,
                frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1410),
                scale: 1
            ),
            ScreenDescriptor(
                displayID: 1,
                frame: CGRect(x: 413, y: -982, width: 1512, height: 982),
                visibleFrame: CGRect(x: 413, y: -982, width: 1512, height: 950),
                scale: 2
            ),
        ])

        #expect(snapshot.screen(displayID: 2)?.visibleFrame == CGRect(x: 0, y: 30, width: 2560, height: 1410))
        #expect(snapshot.screen(displayID: 1)?.visibleFrame == CGRect(x: 413, y: 1472, width: 1512, height: 950))
    }

    @Test func centerlessHybridFrameUsesFallbackDisplay() {
        let snapshot = ScreenSnapshot([
            ScreenDescriptor(
                displayID: 2,
                frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1410),
                scale: 1
            ),
            ScreenDescriptor(
                displayID: 1,
                frame: CGRect(x: 413, y: -982, width: 1512, height: 982),
                visibleFrame: CGRect(x: 413, y: -982, width: 1512, height: 950),
                scale: 2
            ),
        ])
        let hybrid = CGRect(x: 1408, y: 1472, width: 1152, height: 950)
        let builtin = CGRect(x: 413, y: 1472, width: 1512, height: 950)

        #expect(snapshot.displayID(containingCenterOf: hybrid, fallback: 2) == 2)
        #expect(snapshot.displayID(containingCenterOf: builtin, fallback: 2) == 1)
    }

    @Test func topologySignatureIsStableAcrossInputOrder() {
        let left = ScreenDescriptor(
            displayID: 4,
            frame: CGRect(x: -1200, y: 0, width: 1200, height: 900),
            visibleFrame: CGRect(x: -1200, y: 0, width: 1200, height: 870),
            scale: 1
        )
        let right = ScreenDescriptor(
            displayID: 3,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            scale: 2
        )

        #expect(ScreenGeometry.topologySignature([left, right]) == ScreenGeometry.topologySignature([right, left]))
    }

    @Test func offscreenPlacementLeavesOnlyCornerPixelOnSingleScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let context = OffscreenWindowPlacementContext(screen: screen, visibleScreens: [screen])
        let size = CGSize(width: 300, height: 200)

        let origin = OffscreenWindowPlacement.origin(windowSize: size, context: context)
        let hidden = CGRect(origin: origin, size: size)

        #expect(origin == CGPoint(x: 999, y: 799))
        #expect(visibleArea(hidden, in: [screen]) == 1)
    }

    @Test func offscreenPlacementAvoidsNeighborBelowRightCorner() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rightLow = CGRect(x: 1000, y: 700, width: 1000, height: 500)
        let context = OffscreenWindowPlacementContext(screen: screen, visibleScreens: [screen, rightLow])
        let size = CGSize(width: 300, height: 200)

        let origin = OffscreenWindowPlacement.origin(windowSize: size, context: context)
        let hidden = CGRect(origin: origin, size: size)

        #expect(origin == CGPoint(x: -299, y: 799))
        #expect(visibleArea(hidden, in: [screen, rightLow]) == 1)
    }

    @Test func offscreenPlacementUsesTopCornerWhenBothBottomCornersLeak() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let leftLow = CGRect(x: -1000, y: 700, width: 1000, height: 500)
        let rightLow = CGRect(x: 1000, y: 700, width: 1000, height: 500)
        let context = OffscreenWindowPlacementContext(screen: screen, visibleScreens: [screen, leftLow, rightLow])
        let size = CGSize(width: 300, height: 200)

        let origin = OffscreenWindowPlacement.origin(windowSize: size, context: context)
        let hidden = CGRect(origin: origin, size: size)

        #expect(origin == CGPoint(x: 999, y: -199))
        #expect(visibleArea(hidden, in: [screen, leftLow, rightLow]) == 1)
    }

    private func visibleArea(_ rect: CGRect, in screens: [CGRect]) -> CGFloat {
        screens.reduce(0) { result, screen in
            let intersection = rect.intersection(screen)
            guard !intersection.isNull, !intersection.isEmpty else { return result }
            return result + intersection.width * intersection.height
        }
    }
}
