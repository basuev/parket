import CoreGraphics
import Foundation

package struct ScreenDescriptor: Equatable, Sendable {
    package let displayID: CGDirectDisplayID
    package let frame: CGRect
    package let visibleFrame: CGRect
    package let scale: CGFloat

    package init(displayID: CGDirectDisplayID, frame: CGRect, visibleFrame: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
    }
}

package enum ScreenGeometry {
    package static func convertRect(_ rect: CGRect, screens: [ScreenDescriptor]) -> CGRect {
        convertRect(rect, topEdge: topEdge(screens.map(\.frame)))
    }

    package static func convertRect(_ rect: CGRect, topEdge: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: topEdge - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    package static func topEdge(_ frames: [CGRect]) -> CGFloat {
        frames.map(\.maxY).max() ?? 1080
    }

    package static func topologySignature(_ screens: [ScreenDescriptor]) -> String {
        screens
            .sorted { lhs, rhs in
                if lhs.displayID != rhs.displayID {
                    return lhs.displayID < rhs.displayID
                }
                return lhs.frame.origin.x < rhs.frame.origin.x
            }
            .map { screen in
                [
                    "\(screen.displayID)",
                    format(screen.frame),
                    format(screen.visibleFrame),
                    String(format: "%.2f", Double(screen.scale)),
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    private static func format(_ rect: CGRect) -> String {
        [
            rect.origin.x,
            rect.origin.y,
            rect.width,
            rect.height,
        ]
        .map { String(format: "%.1f", Double($0)) }
        .joined(separator: ",")
    }
}
