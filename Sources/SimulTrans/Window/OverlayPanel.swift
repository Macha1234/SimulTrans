import AppKit

final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        isReleasedWhenClosed = false
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        standardWindowButton(.closeButton)?.isHidden = false
        standardWindowButton(.miniaturizeButton)?.isHidden = false
        standardWindowButton(.zoomButton)?.isHidden = false

        // Default size and position at bottom-center of screen
        if let screen = NSScreen.main {
            let width = STTheme.overlayWindowSize.width
            let height = STTheme.overlayWindowSize.height
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.midX - width / 2
            let y = visibleFrame.minY + max(28, visibleFrame.height * 0.05)
            setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
            minSize = STTheme.overlayMinSize
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
