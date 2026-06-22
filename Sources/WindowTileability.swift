import ApplicationServices

package struct TileableWindowAttributes: Equatable {
    var role: String?
    var subrole: String?
    var minimized: Bool
    var fullscreen: Bool
    var modal: Bool
    var hasCloseButton: Bool
    var hasMinimizeButton: Bool
    var hasZoomButton: Bool
    var canSetPosition: Bool
    var canSetSize: Bool

    package init(
        role: String?,
        subrole: String?,
        minimized: Bool,
        fullscreen: Bool,
        modal: Bool,
        hasCloseButton: Bool,
        hasMinimizeButton: Bool,
        hasZoomButton: Bool,
        canSetPosition: Bool,
        canSetSize: Bool
    ) {
        self.role = role
        self.subrole = subrole
        self.minimized = minimized
        self.fullscreen = fullscreen
        self.modal = modal
        self.hasCloseButton = hasCloseButton
        self.hasMinimizeButton = hasMinimizeButton
        self.hasZoomButton = hasZoomButton
        self.canSetPosition = canSetPosition
        self.canSetSize = canSetSize
    }
}

package enum TileableWindowRejectionReason: String, Equatable {
    case role
    case subrole
    case minimized
    case fullscreen
    case modal
    case missingCloseButton = "missing_close_button"
    case missingMinimizeButton = "missing_minimize_button"
    case missingZoomButton = "missing_zoom_button"
    case positionNotSettable = "position_not_settable"
    case sizeNotSettable = "size_not_settable"
}

package enum TileableWindowPolicy {
    package static func accepts(_ attributes: TileableWindowAttributes) -> Bool {
        rejectionReasons(attributes).isEmpty
    }

    package static func rejectionReasons(_ attributes: TileableWindowAttributes) -> [TileableWindowRejectionReason] {
        var reasons: [TileableWindowRejectionReason] = []
        if attributes.role != kAXWindowRole as String { reasons.append(.role) }
        if attributes.subrole != kAXStandardWindowSubrole as String { reasons.append(.subrole) }
        if attributes.minimized { reasons.append(.minimized) }
        if attributes.fullscreen { reasons.append(.fullscreen) }
        if attributes.modal { reasons.append(.modal) }
        if !attributes.hasCloseButton { reasons.append(.missingCloseButton) }
        if !attributes.hasMinimizeButton { reasons.append(.missingMinimizeButton) }
        if !attributes.hasZoomButton { reasons.append(.missingZoomButton) }
        if !attributes.canSetPosition { reasons.append(.positionNotSettable) }
        if !attributes.canSetSize { reasons.append(.sizeNotSettable) }
        return reasons
    }
}
