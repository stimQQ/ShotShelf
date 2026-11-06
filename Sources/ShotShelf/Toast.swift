import AppKit
import SwiftUI

/// A small dark-glass HUD next to the cursor that fades out on its own.
/// Never takes focus or clicks.
@MainActor
final class Toast {
    static let shared = Toast()
    private var panel: NSPanel?
    private var generation = 0

    func show(_ title: String, detail: String? = nil, image: NSImage? = nil) {
        let host = NSHostingView(rootView: ToastView(title: title, detail: detail, image: image))
        let size = host.fittingSize
        let glass = GlassPanel.glass(containing: host, size: size, material: .hudWindow, radius: 16)
        glass.appearance = NSAppearance(named: .darkAqua)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = glass
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        generation += 1
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            guard let self, self.generation == current else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.generation == current { panel.orderOut(nil) }
            }
        }
    }

    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var point = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        if let frame = screen?.visibleFrame {
            point.x = min(max(point.x, frame.minX + 8), frame.maxX - size.width - 8)
            point.y = min(max(point.y, frame.minY + 8), frame.maxY - size.height - 8)
        }
        return point
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

private struct ToastView: View {
    let title: String
    let detail: String?
    let image: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .frame(maxWidth: 220, alignment: .leading)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .fixedSize()
    }
}
