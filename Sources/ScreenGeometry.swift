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
        let topEdge = ScreenGeometry.primaryTopEdge(descriptors.map(\.frame))
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
        convertRect(rect, topEdge: primaryTopEdge(screens.map(\.frame)))
    }

    package static func convertRect(_ rect: CGRect, topEdge: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: topEdge - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    package static func primaryTopEdge(_ frames: [CGRect]) -> CGFloat {
        frames.first?.maxY ?? 1080
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

package struct OffscreenWindowPlacementContext: Equatable, Sendable {
    package let screen: CGRect
    package let visibleScreens: [CGRect]

    package init(screen: CGRect, visibleScreens: [CGRect]) {
        self.screen = screen
        self.visibleScreens = visibleScreens
    }
}

package enum OffscreenWindowPlacement {
    private enum Corner: CaseIterable {
        case bottomRight
        case bottomLeft
        case topRight
        case topLeft
    }

    private static let visibleEdge: CGFloat = 1

    package static func origin(windowSize: CGSize, context: OffscreenWindowPlacementContext) -> CGPoint {
        let size = normalized(windowSize, fallback: context.screen.size)
        let screens = context.visibleScreens.isEmpty ? [context.screen] : context.visibleScreens

        return Corner.allCases
            .enumerated()
            .map { index, corner in
                let origin = origin(windowSize: size, screen: context.screen, corner: corner)
                let rect = CGRect(origin: origin, size: size)
                return (index: index, origin: origin, score: visibleArea(of: rect, in: screens))
            }
            .min { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score < rhs.score
                }
                return lhs.index < rhs.index
            }?
            .origin ?? context.screen.origin
    }

    private static func origin(windowSize size: CGSize, screen: CGRect, corner: Corner) -> CGPoint {
        switch corner {
        case .bottomRight:
            CGPoint(x: screen.maxX - visibleEdge, y: screen.maxY - visibleEdge)
        case .bottomLeft:
            CGPoint(x: screen.minX - size.width + visibleEdge, y: screen.maxY - visibleEdge)
        case .topRight:
            CGPoint(x: screen.maxX - visibleEdge, y: screen.minY - size.height + visibleEdge)
        case .topLeft:
            CGPoint(x: screen.minX - size.width + visibleEdge, y: screen.minY - size.height + visibleEdge)
        }
    }

    private static func normalized(_ size: CGSize, fallback: CGSize) -> CGSize {
        CGSize(
            width: normalized(size.width, fallback: fallback.width),
            height: normalized(size.height, fallback: fallback.height)
        )
    }

    private static func normalized(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        if value.isFinite, value > 0 {
            return value
        }
        if fallback.isFinite, fallback > 0 {
            return fallback
        }
        return 1
    }

    private static func visibleArea(of rect: CGRect, in screens: [CGRect]) -> CGFloat {
        screens.reduce(0) { result, screen in
            result + area(rect.intersection(screen))
        }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        guard !rect.isNull, !rect.isEmpty else { return 0 }
        return rect.width * rect.height
    }
}
