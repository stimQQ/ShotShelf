import AppKit
import SwiftUI

/// Transparent area that moves the window when dragged (borderless windows have no title bar).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Borderless frosted-glass panel with large rounded corners.
/// Non-activating, so it takes keyboard focus without pulling the app to the front
/// (the way Spotlight behaves). Hides on Esc or when it loses focus.
final class GlassPanel: NSPanel, NSWindowDelegate {
    static let cornerRadius: CGFloat = 22
    var onHide: (() -> Void)?

    init(content: NSView, size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        delegate = self
        contentView = GlassPanel.glass(containing: content, size: size,
                                       material: .hudWindow, radius: GlassPanel.cornerRadius)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }

    // With no text field to take Esc, catch it here.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { hide() } else { super.keyDown(with: event) }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func hide() {
        guard isVisible else { return }
        orderOut(nil)
        onHide?()
    }

    /// A behind-window blur view, rounded via mask image, hosting `content`.
    static func glass(containing content: NSView, size: NSSize,
                      material: NSVisualEffectView.Material, radius: CGFloat) -> NSVisualEffectView {
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = material
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.maskImage = mask(radius: radius)
        content.frame = glass.bounds
        content.autoresizingMask = [.width, .height]
        glass.addSubview(content)
        return glass
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
