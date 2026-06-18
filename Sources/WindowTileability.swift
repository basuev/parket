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

package enum TileableWindowPolicy {
    package static func accepts(_ attributes: TileableWindowAttributes) -> Bool {
        attributes.role == kAXWindowRole as String
            && attributes.subrole == kAXStandardWindowSubrole as String
            && !attributes.minimized
            && !attributes.fullscreen
            && !attributes.modal
            && attributes.hasCloseButton
            && attributes.hasMinimizeButton
            && attributes.hasZoomButton
            && attributes.canSetPosition
            && attributes.canSetSize
    }
}
