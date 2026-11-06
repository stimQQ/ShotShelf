import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// One display, frozen at the moment capture started.
struct FrozenScreen {
    let frame: NSRect   // NSScreen.frame, global Cocoa coordinates
    let image: CGImage  // whole display, in pixels
    var scale: CGFloat { CGFloat(image.width) / frame.width }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

@MainActor
enum ScreenGrabber {
    /// A still image of every display, without ShotShelf's own windows.
    static func grabAll() async throws -> [FrozenScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }
        var frozen: [FrozenScreen] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let scale = CGFloat(filter.pointPixelScale)
            let config = SCStreamConfiguration()
            config.width = Int((filter.contentRect.width * scale).rounded())
            config.height = Int((filter.contentRect.height * scale).rounded())
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            frozen.append(FrozenScreen(frame: screen.frame, image: image))
        }
        return frozen
    }

    /// Frames of normal app windows, front to back, in global Cocoa coordinates.
    /// Used to pick a whole window with a single click.
    static func windowFrames() -> [NSRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let me = getpid()
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width > 40, bounds.height > 40
            else { return nil }
            // CoreGraphics measures from the top of the primary display, Cocoa from the bottom.
            return NSRect(x: bounds.minX, y: primaryTop - bounds.maxY, width: bounds.width, height: bounds.height)
        }
    }
}

enum ImageFile {
    /// PNG tagged with the real DPI, so apps paste and preview it at its on-screen size.
    static func writePNG(_ image: CGImage, scale: CGFloat, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        let dpi = 72 * scale
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        return CGImageDestinationFinalize(destination)
    }
}

enum Clipboard {
    @discardableResult
    static func copyImage(at url: URL) -> Bool {
        guard let png = try? Data(contentsOf: url) else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        // Some apps only read TIFF from the pasteboard.
        if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
