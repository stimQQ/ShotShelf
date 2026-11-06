import AppKit
import SwiftUI

/// Click to run `onClick`, drag to hand the file to another app.
/// Drags are copy-only: SwiftUI's .onDrag allows "move", and Finder would then
/// move the screenshot out of the ShotShelf folder, breaking the history entry.
struct FileDragSource: NSViewRepresentable {
    let url: URL
    let image: NSImage?
    let tooltip: String
    let menuItems: [(String, () -> Void)]
    let onClick: () -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }

    func updateNSView(_ view: SourceView, context: Context) {
        view.url = url
        view.image = image
        view.onClick = onClick
        view.menuItems = menuItems
        view.toolTip = tooltip
    }

    final class SourceView: NSView, NSDraggingSource {
        var url: URL?
        var image: NSImage?
        var onClick: (() -> Void)?
        var menuItems: [(String, () -> Void)] = []
        private var mouseDownEvent: NSEvent?

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu()
            for (title, action) in menuItems { menu.addItem(ClosureMenuItem(title: title, handler: action)) }
            return menu
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down = mouseDownEvent, let url else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard hypot(dx, dy) > 3 else { return }
            mouseDownEvent = nil
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(bounds, contents: image ?? NSWorkspace.shared.icon(forFile: url.path))
            beginDraggingSession(with: [item], event: down, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            if mouseDownEvent != nil { onClick?() }
            mouseDownEvent = nil
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
