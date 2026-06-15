import CoreGraphics
import Testing

@testable import ParketCore

@Suite("Screen geometry")
struct ScreenGeometryTests {
    @Test func conversionUsesTopEdgeAcrossAllScreens() {
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
}
