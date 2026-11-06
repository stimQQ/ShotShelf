import AppKit
import ImageIO
import Observation

struct Shot: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    /// nil = OCR not done yet; "" = no text found.
    var text: String?
    var pixelWidth: Int
    var pixelHeight: Int
    /// Pixels per point (2 on Retina).
    var scale: Double
}

/// Screenshot history. Images live in ~/Pictures/ShotShelf, the index in Application Support.
@MainActor
@Observable
final class ShotStore {
    private(set) var shots: [Shot] = [] // newest first
    var permissionGranted = true
    var hotKeyWarning: String?

    let folder: URL
    private let indexURL: URL

    init() {
        let fm = FileManager.default
        if let custom = ProcessInfo.processInfo.environment["SHOTSHELF_DIR"], !custom.isEmpty {
            let root = URL(fileURLWithPath: custom, isDirectory: true)
            folder = root.appendingPathComponent("Shots", isDirectory: true)
            indexURL = root.appendingPathComponent("index.json")
        } else {
            folder = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/ShotShelf", isDirectory: true)
            indexURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ShotShelf/index.json")
        }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? fm.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        load()
    }

    func url(for shot: Shot) -> URL {
        folder.appendingPathComponent(shot.fileName)
    }

    func newShotURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "截图 \(formatter.string(from: Date()))"
        var url = folder.appendingPathComponent("\(base).png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n)).png")
            n += 1
        }
        return url
    }

    /// `screenScale`: backing scale of the captured screen. screencapture writes 72 DPI even
    /// on Retina, so the file alone can't tell how big the shot looked.
    @discardableResult
    func add(url: URL, date: Date = Date(), screenScale: Double? = nil) -> Shot {
        var width = 0, height = 0, scale = screenScale ?? 1
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            if let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 72 { scale = dpi / 72 }
        }
        let shot = Shot(id: UUID(), fileName: url.lastPathComponent, createdAt: date, text: nil,
                        pixelWidth: width, pixelHeight: height, scale: scale)
        shots.insert(shot, at: 0)
        shots.sort { $0.createdAt > $1.createdAt }
        save()
        return shot
    }

    func setText(_ text: String, for id: UUID) {
        guard let i = shots.firstIndex(where: { $0.id == id }) else { return }
        shots[i].text = text
        save()
    }

    /// Shots whose OCR is running right now.
    private(set) var recognizing: Set<UUID> = []

    /// Existing OCR text, or recognize now. OCR only runs when asked for (识字 / 复制文字).
    func text(for shot: Shot) async -> String {
        if let text = shots.first(where: { $0.id == shot.id })?.text { return text }
        recognizing.insert(shot.id)
        defer { recognizing.remove(shot.id) }
        let text = await OCR.recognize(url(for: shot))
        setText(text, for: shot.id)
        return text
    }

    /// Moves the file to the Trash (recoverable).
    func delete(_ shot: Shot) {
        try? FileManager.default.trashItem(at: url(for: shot), resultingItemURL: nil)
        shots.removeAll { $0.id == shot.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let saved = try? decoder.decode([Shot].self, from: data) else { return }
        let fm = FileManager.default
        shots = saved.filter { fm.fileExists(atPath: url(for: $0).path) }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(shots) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
