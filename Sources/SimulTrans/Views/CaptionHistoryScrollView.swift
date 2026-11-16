import AppKit
import SwiftUI

/// Native scrolling keeps mouse wheels, trackpads and scrollbar dragging on
/// the same explicit follow policy. SwiftUI scroll phases omit phase-less wheels.
struct CaptionHistoryScrollView: NSViewRepresentable {
    let content: AnyView
    let followsLatest: Bool
    let onUserScroll: () -> Void

    func makeNSView(context: Context) -> CaptionNativeScrollView {
        CaptionNativeScrollView()
    }

    func updateNSView(_ scroll: CaptionNativeScrollView, context: Context) {
        scroll.onUserScroll = onUserScroll
        scroll.followsLatest = followsLatest
        scroll.setContent(content)
    }
}

final class CaptionNativeScrollView: NSScrollView {
    var followsLatest = true
    var onUserScroll: (() -> Void)?
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var content = AnyView(EmptyView())
    private var updatingLayout = false
    private var lastWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        let scroller = CaptionScroller()
        scroller.onUserScroll = { [weak self] in self?.pauseFollowing() }
        verticalScroller = scroller
        scrollerStyle = .overlay
        host.sizingOptions = [.intrinsicContentSize]
        documentView = host
        contentView.drawsBackground = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setContent(_ content: AnyView) {
        self.content = content
        updateDocument()
    }

    override func layout() {
        super.layout()
        if abs(contentSize.width - lastWidth) > 0.5 { updateDocument() }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaY != 0 { pauseFollowing() }
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if [115, 116, 119, 121, 125, 126].contains(event.keyCode) { pauseFollowing() }
        super.keyDown(with: event)
    }

    private func pauseFollowing() {
        followsLatest = false
        onUserScroll?()
    }

    private func updateDocument() {
        guard !updatingLayout else { return }
        updatingLayout = true
        defer { updatingLayout = false }
        let width = max(1, contentSize.width)
        let previousY = contentView.bounds.origin.y
        lastWidth = width
        host.rootView = AnyView(content.frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true))
        host.layoutSubtreeIfNeeded()
        let height = max(contentSize.height, host.fittingSize.height)
        host.setFrameSize(NSSize(width: width, height: height))
        let bottom = max(0, height - contentSize.height)
        contentView.scroll(to: NSPoint(x: 0, y: followsLatest ? bottom : min(previousY, bottom)))
        reflectScrolledClipView(contentView)
    }
}

private final class CaptionScroller: NSScroller {
    var onUserScroll: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onUserScroll?()
        super.mouseDown(with: event)
    }
}
