import ApplicationServices
import Testing

@testable import ParketCore

@Suite("Window tileability")
struct WindowTileabilityTests {
    @Test func documentWindowIsTileable() {
        #expect(TileableWindowPolicy.accepts(documentWindow()))
    }

    @Test func standardOverlayWithoutWindowControlsIsNotTileable() {
        var attributes = documentWindow()
        attributes.hasCloseButton = false
        attributes.hasMinimizeButton = false
        attributes.hasZoomButton = false

        #expect(!TileableWindowPolicy.accepts(attributes))
    }

    @Test func fixedSizeStandardDialogIsNotTileable() {
        var attributes = documentWindow()
        attributes.canSetSize = false

        #expect(!TileableWindowPolicy.accepts(attributes))
    }

    @Test func modalStandardWindowIsNotTileable() {
        var attributes = documentWindow()
        attributes.modal = true

        #expect(!TileableWindowPolicy.accepts(attributes))
    }

    private func documentWindow() -> TileableWindowAttributes {
        TileableWindowAttributes(
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            minimized: false,
            fullscreen: false,
            modal: false,
            hasCloseButton: true,
            hasMinimizeButton: true,
            hasZoomButton: true,
            canSetPosition: true,
            canSetSize: true
        )
    }
}
