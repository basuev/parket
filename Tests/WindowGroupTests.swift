import CoreGraphics
import Testing

@testable import ParketCore

@Suite("Window grouping")
struct WindowGroupTests {
    let frame = CGRect(x: 256, y: 128, width: 960, height: 640)

    @Test func smallFrameDriftKeepsGroup() {
        let shifted = CGRect(x: 259, y: 131, width: 956, height: 643)
        #expect(WindowFrameKey(frame) == WindowFrameKey(shifted))
    }

    @Test func largeFrameDriftChangesGroup() {
        let shifted = CGRect(x: 288, y: 128, width: 960, height: 640)
        #expect(WindowFrameKey(frame) != WindowFrameKey(shifted))
    }

    @Test func pidSeparatesEqualFrames() {
        let left = WindowGroupKey(pid: 10, identity: .element(1))
        let right = WindowGroupKey(pid: 11, identity: .element(1))
        #expect(left != right)
    }

    @Test func equalFramesDoNotGroupSeparateElements() {
        let left = WindowGroupKey(pid: 10, identity: .element(1))
        let right = WindowGroupKey(pid: 10, identity: .element(2))
        #expect(!WindowGrouping.matches(lhsGroup: left, lhsFrame: frame, rhsGroup: right, rhsFrame: frame))
    }

    @Test func overlapGroupsSharedNativeTabGroup() {
        let shifted = CGRect(x: 260, y: 132, width: 950, height: 632)
        let left = WindowGroupKey(pid: 10, identity: .nativeTabGroup(1))
        let right = WindowGroupKey(pid: 10, identity: .nativeTabGroup(1))
        #expect(WindowGrouping.matches(lhsGroup: left, lhsFrame: frame, rhsGroup: right, rhsFrame: shifted))
    }

    @Test func overlapDoesNotGroupDifferentPids() {
        let shifted = CGRect(x: 260, y: 132, width: 950, height: 632)
        let left = WindowGroupKey(pid: 10, identity: .nativeTabGroup(1))
        let right = WindowGroupKey(pid: 11, identity: .nativeTabGroup(1))
        #expect(!WindowGrouping.matches(lhsGroup: left, lhsFrame: frame, rhsGroup: right, rhsFrame: shifted))
    }

    @Test func separatedFramesDoNotGroupByOverlap() {
        let shifted = CGRect(x: 1400, y: 128, width: 960, height: 640)
        let left = WindowGroupKey(pid: 10, identity: .nativeTabGroup(1))
        let right = WindowGroupKey(pid: 10, identity: .nativeTabGroup(1))
        #expect(!WindowGrouping.matches(lhsGroup: left, lhsFrame: frame, rhsGroup: right, rhsFrame: shifted))
    }

    @Test func equalFramesDoNotGroupDifferentNativeTabGroups() {
        let left = WindowGroupKey(pid: 10, identity: .nativeTabGroup(1))
        let right = WindowGroupKey(pid: 10, identity: .nativeTabGroup(2))
        #expect(!WindowGrouping.matches(lhsGroup: left, lhsFrame: frame, rhsGroup: right, rhsFrame: frame))
    }
}
