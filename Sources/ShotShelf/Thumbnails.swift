import AppKit
import ImageIO

/// Downsampled previews so the history list never decodes full-size screenshots.
final class Thumbnails: @unchecked Sendable {
    static let shared = Thumbnails()
    private let cache = NSCache<NSString, NSImage>()

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    func load(_ url: URL) async -> NSImage? {
        if let image = cached(url) { return image }
        let image = await Task.detached(priority: .userInitiated) {
            Thumbnails.make(url, maxPixel: 800)
        }.value
        if let image { cache.setObject(image, forKey: url.path as NSString) }
        return image
    }

    static func make(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
