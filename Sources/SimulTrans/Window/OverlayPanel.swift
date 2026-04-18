import AppKit

final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView,
                        .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        // Default size and position at bottom-center of screen
        if let screen = NSScreen.main {
            let width = STTheme.overlayWindowSize.width
            let height = STTheme.overlayWindowSize.height
            let x = (screen.frame.width - width) / 2
            let y = screen.frame.height * 0.05
            setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
            minSize = STTheme.overlayMinSize
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
