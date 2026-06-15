import CoreGraphics
import Testing

@testable import ParketCore

@Suite("Tiler")
struct TilerTests {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func emptyReturnsEmpty() {
        let frames = Tiler.calculateFrames(count: 0, screen: screen, layout: .tile)
        #expect(frames.isEmpty)
    }

    @Test func singleWindowCoversScreen() {
        let frames = Tiler.calculateFrames(count: 1, screen: screen, layout: .tile)
        #expect(frames == [screen])
    }

    @Test func singleWindowTileAndMonocleMatch() {
        let tile = Tiler.calculateFrames(count: 1, screen: screen, layout: .tile)
        let monocle = Tiler.calculateFrames(count: 1, screen: screen, layout: .monocle)
        #expect(tile == monocle)
    }

    @Test func twoWindowsUseMasterRatio() {
        let frames = Tiler.calculateFrames(count: 2, screen: screen, layout: .tile, masterRatio: 0.55)
        let masterWidth = floor(screen.width * 0.55)
        #expect(frames.count == 2)
        #expect(frames[0].width == masterWidth)
        #expect(frames[1].width == screen.width - masterWidth)
        #expect(frames[0].height == 1080)
        #expect(frames[1].height == 1080)
    }

    @Test func fourWindowsUseExpectedWorkspaceOneStackSlots() {
        let display = CGRect(x: 0, y: 30, width: 2560, height: 1410)
        let frames = Tiler.calculateFrames(count: 4, screen: display, layout: .tile, masterRatio: 0.55)

        #expect(
            frames == [
                CGRect(x: 0, y: 30, width: 1408, height: 1410),
                CGRect(x: 1408, y: 30, width: 1152, height: 470),
                CGRect(x: 1408, y: 500, width: 1152, height: 470),
                CGRect(x: 1408, y: 970, width: 1152, height: 470),
            ])
    }

    @Test func stackWindowsHaveNoPositiveGaps() {
        for count in 4...12 {
            let frames = Tiler.calculateFrames(count: count, screen: screen, layout: .tile)
            let stack = frames.dropFirst().sorted { $0.origin.y < $1.origin.y }
            for i in 1..<stack.count {
                let previousBottom = stack[i - 1].origin.y + stack[i - 1].height
                #expect(abs(stack[i].origin.y - previousBottom) < 0.001)
            }
        }
    }

    @Test func tileOutputCoversScreenArea() {
        for count in 1...20 {
            let frames = Tiler.calculateFrames(count: count, screen: screen, layout: .tile)
            let totalArea = frames.reduce(0.0) { $0 + $1.width * $1.height }
            #expect(abs(totalArea - screen.width * screen.height) < 1.0)
        }
    }

    @Test func validScreensNeverProduceNegativeSizes() {
        let screens = [
            screen,
            CGRect(x: -1200, y: 20, width: 1200, height: 900),
            CGRect(x: 100, y: 50, width: 1440, height: 932),
        ]

        for screen in screens {
            for count in 1...20 {
                for layout in [Layout.tile, .monocle] {
                    let frames = Tiler.calculateFrames(count: count, screen: screen, layout: layout)
                    #expect(frames.allSatisfy { $0.width >= 0 && $0.height >= 0 })
                }
            }
        }
    }

    @Test func offsetScreensKeepOrigins() {
        let offset = CGRect(x: 100, y: 50, width: 1920, height: 1080)
        let frames = Tiler.calculateFrames(count: 2, screen: offset, layout: .tile, masterRatio: 0.55)
        let masterWidth = floor(offset.width * 0.55)
        #expect(frames[0].origin.x == 100)
        #expect(frames[0].origin.y == 50)
        #expect(frames[1].origin.x == offset.origin.x + masterWidth)
        #expect(frames[1].origin.y == 50)
    }

    @Test func monocleGivesEveryWindowTheVisibleFrame() {
        let frames = Tiler.calculateFrames(count: 5, screen: screen, layout: .monocle)
        #expect(frames.count == 5)
        #expect(frames.allSatisfy { $0 == screen })
    }
}
