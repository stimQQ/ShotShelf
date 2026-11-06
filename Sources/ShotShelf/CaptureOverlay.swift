import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum CaptureOutcome {
    case copyImage(CGImage, scale: CGFloat)
    case recognize(CGImage, scale: CGFloat)
}

/// WeChat-style capture: every display is frozen and covered; the user drags a region
/// (or clicks a window), then a toolbar under the selection offers 打码 / 识字 / 完成.
@MainActor
final class CaptureOverlay {
    private static var current: CaptureOverlay?
    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<CaptureOutcome?, Never>?

    /// `recognizeOnSelect`: ⌥⇧O — skip the toolbar and go straight to OCR.
    static func run(_ screens: [FrozenScreen], recognizeOnSelect: Bool) async -> CaptureOutcome? {
        current?.finish(nil)
        let overlay = CaptureOverlay()
        current = overlay
        return await withCheckedContinuation { continuation in
            overlay.continuation = continuation
            overlay.show(screens, recognizeOnSelect: recognizeOnSelect)
        }
    }

    private func show(_ screens: [FrozenScreen], recognizeOnSelect: Bool) {
        let windowFrames = ScreenGrabber.windowFrames()
        for screen in screens {
            let view = CaptureView(frozen: screen, windowFrames: windowFrames, recognizeOnSelect: recognizeOnSelect)
            view.onBegin = { [weak self, weak view] in
                for window in self?.windows ?? [] where window.captureView !== view {
                    window.captureView.reset()
                }
            }
            view.onFinish = { [weak self] outcome in self?.finish(outcome) }
            let window = OverlayWindow(view: view, frame: screen.frame)
            windows.append(window)
            window.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        let target = windows.first { NSMouseInRect(mouse, $0.frame, false) } ?? windows.first
        target?.makeKey()
        target?.makeFirstResponder(target?.captureView)
        NSCursor.crosshair.set()
    }

    private func finish(_ outcome: CaptureOutcome?) {
        guard let continuation else { return }
        self.continuation = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        if Self.current === self { Self.current = nil }
        NSCursor.arrow.set()
        continuation.resume(returning: outcome)
    }
}

/// Covers one whole display, menu bar included. Non-activating, so the app you were in stays active.
final class OverlayWindow: NSPanel {
    let captureView: CaptureView

    init(view: CaptureView, frame: NSRect) {
        captureView = view
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true
        contentView = view
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    // Keep the window over the menu bar instead of letting AppKit push it below.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@Observable
final class CaptureToolbarModel {
    var mosaicOn = false
    var canUndo = false
}

final class CaptureView: NSView {
    var onBegin: (() -> Void)?
    var onFinish: ((CaptureOutcome?) -> Void)?

    private let frozen: FrozenScreen
    private let windowRects: [NSRect] // view coordinates, front to back
    private let recognizeOnSelect: Bool
    private let model = CaptureToolbarModel()
    private var toolbar: NSView!

    private enum Drag {
        case none
        case selecting(from: NSPoint)
        case moving(from: NSPoint, original: NSRect)
        case resizing(Handle, original: NSRect)
        case mosaic(from: NSPoint)
    }

    private var drag = Drag.none
    private var selection: NSRect?
    private var hoverRect: NSRect?
    private var mosaics: [NSRect] = []
    private var pendingMosaic: NSRect?
    private lazy var pixelated: CGImage? = Self.pixelate(frozen.image, block: 12 * frozen.scale)

    init(frozen: FrozenScreen, windowFrames: [NSRect], recognizeOnSelect: Bool) {
        self.frozen = frozen
        self.recognizeOnSelect = recognizeOnSelect
        let bounds = NSRect(origin: .zero, size: frozen.frame.size)
        windowRects = windowFrames
            .map { $0.offsetBy(dx: -frozen.frame.minX, dy: -frozen.frame.minY).intersection(bounds) }
            .filter { !$0.isEmpty }
        super.init(frame: bounds)

        let bar = CaptureToolbar(
            model: model,
            onMosaic: { [weak self] in self?.toggleMosaic() },
            onRecognize: { [weak self] in self?.finish(recognize: true) },
            onUndo: { [weak self] in self?.undo() },
            onCancel: { [weak self] in self?.onFinish?(nil) },
            onDone: { [weak self] in self?.finish(recognize: false) })
        toolbar = FirstMouseHostingView(rootView: bar)
        toolbar.isHidden = true
        addSubview(toolbar)

        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Back to "nothing selected" (another display took over, or right-click).
    func reset() {
        selection = nil
        hoverRect = nil
        mosaics.removeAll()
        pendingMosaic = nil
        model.mosaicOn = false
        model.canUndo = false
        toolbar.isHidden = true
        drag = .none
        needsDisplay = true
    }

    // MARK: - Actions

    private func toggleMosaic() {
        model.mosaicOn.toggle()
        needsDisplay = true
    }

    private func undo() {
        guard !mosaics.isEmpty else { return }
        mosaics.removeLast()
        model.canUndo = !mosaics.isEmpty
        needsDisplay = true
    }

    private func finish(recognize: Bool) {
        guard let image = renderSelection() else {
            onFinish?(nil)
            return
        }
        onFinish?(recognize ? .recognize(image, scale: frozen.scale) : .copyImage(image, scale: frozen.scale))
    }

    private func selectionDone() {
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            reset()
            return
        }
        if recognizeOnSelect {
            finish(recognize: true)
        } else {
            layoutToolbar()
        }
    }

    // MARK: - Mouse & keys

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        let p = point(event)
        guard let sel = selection else {
            drag = .selecting(from: p)
            onBegin?()
            return
        }
        if event.clickCount == 2, sel.contains(p), !model.mosaicOn {
            finish(recognize: false)
        } else if model.mosaicOn, sel.contains(p) {
            drag = .mosaic(from: p)
        } else if let handle = Handle.hit(p, in: sel) {
            drag = .resizing(handle, original: sel)
        } else if sel.contains(p) {
            drag = .moving(from: p, original: sel)
        } else if mosaics.isEmpty {
            // Dragging outside starts over, unless that would throw away mosaic work.
            reset()
            drag = .selecting(from: p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        switch drag {
        case .none:
            return
        case .selecting(let from):
            guard selection != nil || hypot(p.x - from.x, p.y - from.y) > 3 else { return }
            selection = Self.rect(from, p)
            hoverRect = nil
            toolbar.isHidden = true
        case .moving(let from, let original):
            var moved = original.offsetBy(dx: p.x - from.x, dy: p.y - from.y)
            moved.origin.x = min(max(moved.minX, 0), bounds.width - moved.width)
            moved.origin.y = min(max(moved.minY, 0), bounds.height - moved.height)
            selection = moved
            toolbar.isHidden = true
        case .resizing(let handle, let original):
            selection = handle.resize(original, to: p)
            toolbar.isHidden = true
        case .mosaic(let from):
            if let sel = selection { pendingMosaic = Self.rect(from, p).intersection(sel) }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case .none:
            break
        case .selecting:
            // A click without dragging picks the window under the mouse (or the whole screen).
            if selection == nil { selection = hoverRect ?? bounds }
            hoverRect = nil
            selectionDone()
        case .moving, .resizing:
            selectionDone()
        case .mosaic:
            if let rect = pendingMosaic, rect.width >= 3, rect.height >= 3 {
                mosaics.append(rect)
                model.canUndo = true
            }
            pendingMosaic = nil
        }
        drag = .none
        needsDisplay = true
        updateCursor(at: point(event))
    }

    override func rightMouseDown(with event: NSEvent) {
        if selection != nil { reset() } else { onFinish?(nil) }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        if selection == nil, case .none = drag {
            let hit = windowRects.first { $0.contains(p) }
            if hit != hoverRect {
                hoverRect = hit
                needsDisplay = true
            }
        }
        updateCursor(at: p)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: point(event))
    }

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch event.keyCode {
        case 53: // Esc
            onFinish?(nil)
        case 36, 76: // Return, Enter
            if selection != nil { finish(recognize: false) }
        default:
            if command && key == "z" {
                undo()
            } else if command && key == "c" && selection != nil {
                finish(recognize: false)
            }
        }
    }

    private func point(_ event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow, from: nil)
        return NSPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func updateCursor(at p: NSPoint) {
        let cursor: NSCursor
        if !toolbar.isHidden && toolbar.frame.contains(p) {
            cursor = .arrow
        } else if let sel = selection {
            if model.mosaicOn && sel.contains(p) {
                cursor = .crosshair
            } else if let handle = Handle.hit(p, in: sel) {
                cursor = handle.cursor
            } else if sel.contains(p) {
                cursor = .openHand
            } else {
                cursor = mosaics.isEmpty ? .crosshair : .arrow
            }
        } else {
            cursor = .crosshair
        }
        cursor.set()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(frozen.image, in: bounds)

        let masked = mosaics + (pendingMosaic.map { [$0] } ?? [])
        if !masked.isEmpty, let pixelated {
            context.saveGState()
            context.clip(to: masked)
            context.draw(pixelated, in: bounds)
            context.restoreGState()
        }

        let hole = selection ?? hoverRect
        context.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        if let hole {
            context.addRect(bounds)
            context.addRect(hole)
            context.fillPath(using: .evenOdd)
        } else {
            context.fill(bounds)
        }

        let accent = NSColor.controlAccentColor
        if let hole {
            let width: CGFloat = selection == nil ? 3 : 1.5
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(width)
            context.stroke(hole.insetBy(dx: -width / 2, dy: -width / 2))
        }
        if let sel = selection {
            if !model.mosaicOn {
                context.setFillColor(accent.cgColor)
                for handle in Handle.all {
                    let c = handle.point(in: sel)
                    context.fillEllipse(in: NSRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
                }
            }
            var label = "\(Int((sel.width * frozen.scale).rounded())) × \(Int((sel.height * frozen.scale).rounded()))"
            if model.mosaicOn { label += L("   在选区里拖动，框住要打码的地方", "   Drag inside the selection to cover areas") }
            drawLabel(label, near: sel)
        } else if recognizeOnSelect {
            drawLabel(L("框选要识别文字的区域，Esc 取消", "Select the text to recognize · Esc to cancel"),
                      near: NSRect(x: bounds.midX - 120, y: bounds.maxY - 90, width: 0, height: 0))
        }
    }

    /// Dark pill above the rect's top-left corner (inside it if there's no room above).
    private func drawLabel(_ text: String, near rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var box = NSRect(x: rect.minX, y: rect.maxY + 6, width: size.width + 18, height: size.height + 10)
        if box.maxY > bounds.maxY - 4 {
            box.origin = NSPoint(x: rect.minX + 6, y: rect.maxY - box.height - 6)
        }
        box.origin.x = min(max(box.minX, 4), bounds.maxX - box.width - 4)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + 9, y: box.minY + 5), withAttributes: attributes)
    }

    /// Under the selection, right-aligned; above it or inside when there's no room.
    private func layoutToolbar() {
        guard let sel = selection else { return }
        let size = toolbar.fittingSize
        let gap: CGFloat = 8
        var x = sel.maxX - size.width
        var y = sel.minY - size.height - gap
        if y < gap { y = sel.maxY + gap }
        if y + size.height > bounds.height - gap {
            y = sel.minY + gap
            x = sel.maxX - size.width - gap
        }
        x = min(max(x, gap), bounds.width - size.width - gap)
        toolbar.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        toolbar.isHidden = false
    }

    // MARK: - Output

    /// The selected pixels with mosaics burned in.
    private func renderSelection() -> CGImage? {
        guard let sel = selection else { return nil }
        let s = frozen.scale
        let px = NSRect(x: sel.minX * s, y: sel.minY * s, width: sel.width * s, height: sel.height * s).integral
        let imageHeight = CGFloat(frozen.image.height)
        // CGImage cropping counts from the top.
        let crop = CGRect(x: px.minX, y: imageHeight - px.maxY, width: px.width, height: px.height)
        guard let base = frozen.image.cropping(to: crop) else { return nil }
        if mosaics.isEmpty { return base }

        // Never fall back to the unmasked image: no output beats leaking what was covered.
        guard let pixelated else { return nil }
        let spaces = [base.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = spaces.lazy.compactMap({
            CGContext(data: nil, width: Int(px.width), height: Int(px.height), bitsPerComponent: 8,
                      bytesPerRow: 0, space: $0, bitmapInfo: bitmapInfo)
        }).first else { return nil }
        let whole = CGRect(x: -px.minX, y: -px.minY, width: CGFloat(frozen.image.width), height: imageHeight)
        context.draw(frozen.image, in: whole)
        context.clip(to: mosaics.map {
            CGRect(x: $0.minX * s - px.minX, y: $0.minY * s - px.minY, width: $0.width * s, height: $0.height * s)
        })
        context.draw(pixelated, in: whole)
        return context.makeImage()
    }

    private static func pixelate(_ image: CGImage, block: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(block)
        filter.center = .zero
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }

    private static func rect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Dev

    /// Preset state for the offscreen snapshot.
    func debugShow(selection: NSRect, mosaics: [NSRect], mosaicOn: Bool) {
        self.selection = selection
        self.mosaics = mosaics
        model.mosaicOn = mosaicOn
        model.canUndo = !mosaics.isEmpty
        layoutToolbar()
        needsDisplay = true
    }

    func debugRender() -> CGImage? { renderSelection() }
}

/// The eight grab points around a selection.
private struct Handle {
    var left = false, right = false, top = false, bottom = false

    static let all: [Handle] = [
        Handle(left: true, top: true), Handle(top: true), Handle(right: true, top: true),
        Handle(left: true), Handle(right: true),
        Handle(left: true, bottom: true), Handle(bottom: true), Handle(right: true, bottom: true),
    ]

    func point(in r: NSRect) -> NSPoint {
        NSPoint(x: left ? r.minX : right ? r.maxX : r.midX,
                y: bottom ? r.minY : top ? r.maxY : r.midY)
    }

    static func hit(_ p: NSPoint, in r: NSRect) -> Handle? {
        all.first { hypot($0.point(in: r).x - p.x, $0.point(in: r).y - p.y) <= 8 }
    }

    func resize(_ r: NSRect, to p: NSPoint) -> NSRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        if left { minX = p.x }
        if right { maxX = p.x }
        if bottom { minY = p.y }
        if top { maxY = p.y }
        return NSRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    var cursor: NSCursor {
        if (left || right) && !(top || bottom) { return .resizeLeftRight }
        if (top || bottom) && !(left || right) { return .resizeUpDown }
        return .crosshair
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Dark, high-contrast bar under the selection.
struct CaptureToolbar: View {
    let model: CaptureToolbarModel
    var onMosaic: () -> Void
    var onRecognize: () -> Void
    var onUndo: () -> Void
    var onCancel: () -> Void
    var onDone: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            tool(L("打码", "Mosaic"), icon: "checkerboard.rectangle", active: model.mosaicOn,
                 help: L("打码：在选区里拖动，框住要遮挡的地方", "Mosaic: drag inside the selection over what to hide"), action: onMosaic)
            tool(L("识字", "OCR"), icon: "text.viewfinder", active: false,
                 help: L("识别选区里的文字并复制", "Recognize the text and copy it"), action: onRecognize)
            iconButton("arrow.uturn.backward", help: L("撤销打码 ⌘Z", "Undo mosaic ⌘Z"), action: onUndo)
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.35)
            iconButton("xmark", help: L("取消 Esc", "Cancel (Esc)"), action: onCancel)
            Button(action: onDone) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(L("完成", "Done"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("复制图片（回车，或双击选区）", "Copy image (Return, or double-click the selection)"))
            .padding(.leading, 4)
        }
        .padding(4)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fixedSize()
    }

    private func tool(_ title: String, icon: String, active: Bool, help: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(active ? Color.black : Color.white)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(active ? Color.white : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
