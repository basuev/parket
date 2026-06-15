import CoreGraphics

package struct WindowGroupKey: Hashable, Sendable {
    let pid: pid_t
    let identity: WindowIdentityKey

    package init(pid: pid_t, identity: WindowIdentityKey) {
        self.pid = pid
        self.identity = identity
    }
}

package enum WindowIdentityKey: Hashable, Sendable {
    case element(UInt)
    case nativeTabGroup(UInt)
}

package struct WindowFrameKey: Hashable, Sendable {
    private static let unit: CGFloat = 16

    let x: Int
    let y: Int
    let width: Int
    let height: Int

    package init(_ frame: CGRect) {
        x = Self.quantize(frame.origin.x)
        y = Self.quantize(frame.origin.y)
        width = Self.quantize(frame.width)
        height = Self.quantize(frame.height)
    }

    private static func quantize(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 0 }
        return Int((value / unit).rounded())
    }
}

package enum WindowGrouping {
    package static let nativeTabOverlapThreshold: CGFloat = 0.88

    package static func matches(
        lhsGroup: WindowGroupKey,
        lhsFrame: CGRect,
        rhsGroup: WindowGroupKey,
        rhsFrame: CGRect
    ) -> Bool {
        lhsGroup == rhsGroup && overlapRatio(lhsFrame, rhsFrame) >= nativeTabOverlapThreshold
    }

    package static func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let area = min(lhs.width * lhs.height, rhs.width * rhs.height)
        guard area > 0 else { return 0 }
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return max(0, intersection.width * intersection.height) / area
    }
}
