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

package struct ConvertedScreenDescriptor: Equatable, Sendable {
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

package struct ScreenSnapshot: Equatable, Sendable {
    package let screens: [ConvertedScreenDescriptor]

    package init(_ descriptors: [ScreenDescriptor]) {
        let topEdge = ScreenGeometry.topEdge(descriptors.map(\.frame))
        screens = descriptors.map { descriptor in
            ConvertedScreenDescriptor(
                displayID: descriptor.displayID,
                frame: ScreenGeometry.convertRect(descriptor.frame, topEdge: topEdge),
                visibleFrame: ScreenGeometry.convertRect(descriptor.visibleFrame, topEdge: topEdge),
                scale: descriptor.scale
            )
        }
    }

    package func screen(displayID: CGDirectDisplayID) -> ConvertedScreenDescriptor? {
        screens.first { $0.displayID == displayID }
    }

    package func displayID(containingCenterOf frame: CGRect, fallback: CGDirectDisplayID?) -> CGDirectDisplayID? {
        guard frame.width > 0, frame.height > 0 else { return fallback ?? screens.first?.displayID }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.first { $0.frame.contains(center) }?.displayID ?? fallback ?? screens.first?.displayID
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
