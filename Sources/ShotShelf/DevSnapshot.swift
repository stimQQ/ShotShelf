import AppKit
import SwiftUI

/// Dev-only views of the UI without clicking around.
/// Run with SHOTSHELF_DIR pointing at a scratch folder so real history is untouched.
@MainActor
enum DevSnapshot {
    /// Renders the panel offscreen to a PNG (no behind-window blur).
    static func run(output: URL, images: [URL], dark: Bool) {
        let store = makeStore(images: images)
        let host = NSHostingView(rootView: PanelView(store: store, actions: .noop)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: PanelView.size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: output)
        print("Wrote \(output.path)")
    }

    /// Shows the real glass panel (top-right of the primary screen) plus a toast for `seconds`.
    static func preview(seconds: Double, images: [URL], dark: Bool, toast: Bool = true) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = makeStore(images: images)
        let host = NSHostingView(rootView: PanelView(store: store, actions: .noop))
        let panel = GlassPanel(content: host, size: PanelView.size)
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if let frame = NSScreen.screens.first?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - PanelView.size.width - 12,
                                         y: frame.maxY - PanelView.size.height - 6))
        }
        panel.orderFrontRegardless()
        let toastImage = images.first.flatMap { Thumbnails.make($0, maxPixel: 160) }
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if toast { Toast.shared.show("已复制 23 字", detail: "明天下午三点在3号会议室开评审会", image: toastImage) }
            RunLoop.main.run(until: min(end, Date().addingTimeInterval(1)))
        }
    }

    /// Renders the capture screen offscreen over `background` (a full-screen PNG at 2x):
    /// a selection with one mosaic box and the toolbar. Also writes the cropped output next to it.
    static func overlay(output: URL, background: URL) {
        guard let source = CGImageSourceCreateWithURL(background as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let size = NSSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
        let frozen = FrozenScreen(frame: NSRect(origin: .zero, size: size), image: image)
        let view = CaptureView(frozen: frozen, windowFrames: [], recognizeOnSelect: false)
        let selection = NSRect(x: size.width * 0.3, y: size.height * 0.35, width: size.width * 0.4, height: size.height * 0.4)
        let mosaic = NSRect(x: selection.minX + 20, y: selection.maxY - 90, width: selection.width * 0.5, height: 60)
        view.debugShow(selection: selection, mosaics: [mosaic], mosaicOn: true)

        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: -8000, y: -8000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1))

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: output)
        if let cropped = view.debugRender() {
            let croppedURL = output.deletingPathExtension().appendingPathExtension("crop.png")
            _ = ImageFile.writePNG(cropped, scale: 2, to: croppedURL)
            print("Wrote \(croppedURL.path)")
        }
        print("Wrote \(output.path)")
    }

    /// Grabs every display through ScreenCaptureKit into `folder` (checks the capture path).
    static func grab(folder: URL) async {
        for round in 1...3 {
            let start = Date()
            _ = try? await ScreenGrabber.grabAll()
            print("round \(round): \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        }
        do {
            for (index, screen) in try await ScreenGrabber.grabAll().enumerated() {
                let url = folder.appendingPathComponent("display-\(index).png")
                _ = ImageFile.writePNG(screen.image, scale: screen.scale, to: url)
                print("Wrote \(url.path)  \(screen.image.width)x\(screen.image.height) @\(screen.scale)x")
            }
        } catch {
            print("Grab failed: \(error)")
        }
    }

    private static func makeStore(images: [URL]) -> ShotStore {
        let store = ShotStore()
        for (index, source) in images.enumerated() {
            let destination = store.newShotURL()
            try? FileManager.default.copyItem(at: source, to: destination)
            // Spread samples over yesterday and today, oldest first.
            let date = Date().addingTimeInterval(index < 2 ? -86_400 + Double(index * 600)
                                                           : Double((index - images.count) * 600))
            let shot = store.add(url: destination, date: date)
            store.setText(OCR.text(from: destination), for: shot.id)
        }
        return store
    }
}
