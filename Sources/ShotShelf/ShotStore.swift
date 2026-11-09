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
    /// Whether the text bubble shows under the image. Text read in the background only feeds
    /// search; it shows once the user asks for it. nil in older indexes, where text only
    /// existed after the user asked.
    var textShown: Bool?

    var showsText: Bool { textShown ?? (text?.isEmpty == false) }
}

/// Screenshot history. Images live in ~/Pictures/ShotShelf, the index in Application Support.
@MainActor
@Observable
final class ShotStore {
    private(set) var shots: [Shot] = [] // newest first
    var permissionGranted = true
    var busyHotKeys: [String] = [] // hot keys another app already owns, e.g. "⌥⇧A"

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
        let base = "\(L("截图", "Screenshot")) \(formatter.string(from: Date()))"
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
        indexInBackground()
        return shot
    }

    /// `show`: put the text bubble under the image (the user asked for the text).
    func setText(_ text: String, for id: UUID, show: Bool = true) {
        guard let i = shots.firstIndex(where: { $0.id == id }) else { return }
        shots[i].text = text
        if show {
            shots[i].textShown = true
        } else if shots[i].textShown == nil {
            shots[i].textShown = false
        }
        save()
    }

    /// Shots whose OCR the user is waiting for right now.
    private(set) var recognizing: Set<UUID> = []

    /// Existing OCR text, or recognize now (识字 / 复制文字). Either way the text bubble shows.
    func text(for shot: Shot) async -> String {
        if let i = shots.firstIndex(where: { $0.id == shot.id }), let text = shots[i].text {
            if shots[i].textShown != true {
                shots[i].textShown = true
                save()
            }
            return text
        }
        recognizing.insert(shot.id)
        defer { recognizing.remove(shot.id) }
        let text = await OCR.recognize(url(for: shot))
        setText(text, for: shot.id)
        return text
    }

    // MARK: - Search

    private var indexing: Task<Void, Never>?

    /// Shots whose text hasn't been read yet, so search can't find them.
    var unindexedCount: Int { shots.reduce(0) { $0 + ($1.text == nil ? 1 : 0) } }

    /// Reads the text of every shot that hasn't been read yet, newest first, one at a time at
    /// low priority. On-device (Vision), so nothing leaves the Mac.
    func indexInBackground() {
        guard indexing == nil else { return }
        indexing = Task { [weak self] in
            while let self,
                  let shot = self.shots.first(where: { $0.text == nil && !self.recognizing.contains($0.id) }) {
                let text = await OCR.recognize(self.url(for: shot), priority: .utility)
                if self.shots.first(where: { $0.id == shot.id })?.text == nil {
                    self.setText(text, for: shot.id, show: false)
                }
            }
            self?.indexing = nil
        }
    }

    var isSearching = false
    var searchQuery = ""

    func endSearch() {
        isSearching = false
        searchQuery = ""
    }

    static let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    static func searchTokens(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Shots whose text contains every word of the query (all shots for an empty query).
    var searchResults: [Shot] {
        let tokens = Self.searchTokens(searchQuery)
        guard !tokens.isEmpty else { return shots }
        return shots.filter { shot in
            guard let text = shot.text else { return false }
            return tokens.allSatisfy { text.range(of: $0, options: Self.searchOptions) != nil }
        }
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
        indexInBackground()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(shots) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
