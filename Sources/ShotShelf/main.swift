import AppKit

var args = CommandLine.arguments

// `--search <words>` opens the panel's search with these words (dev snapshots and previews).
var searchQuery: String?
if let i = args.firstIndex(of: "--search"), i + 1 < args.count {
    searchQuery = args[i + 1]
    args.removeSubrange(i...(i + 1))
}

// Debug helpers: `ShotShelf --ocr <image>` prints recognized text,
// `ShotShelf --snapshot <out.png> [--dark] <images...>` renders the panel offscreen.
if let i = args.firstIndex(of: "--ocr"), i + 1 < args.count {
    print(OCR.text(from: URL(fileURLWithPath: args[i + 1])))
    exit(0)
}

let app = NSApplication.shared

// Dev previews: `--en` / `--zh` show that language without saving the choice.
if args.contains("--en") { Language.shared.set(.english, persist: false) }
if args.contains("--zh") { Language.shared.set(.chinese, persist: false) }

if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    let output = URL(fileURLWithPath: args[i + 1])
    let dark = args.contains("--dark")
    let images = args[(i + 2)...].filter { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) }
    MainActor.assumeIsolated { DevSnapshot.run(output: output, images: images, dark: dark, search: searchQuery) }
    exit(0)
}

if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
    let seconds = Double(args[i + 1]) ?? 5
    let dark = args.contains("--dark")
    let images = args[(i + 2)...].filter { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) }
    MainActor.assumeIsolated { DevSnapshot.preview(seconds: seconds, images: images, dark: dark, toast: !args.contains("--no-toast"), search: searchQuery) }
    exit(0)
}

if let i = args.firstIndex(of: "--overlay-snapshot"), i + 2 < args.count {
    let output = URL(fileURLWithPath: args[i + 1]), background = URL(fileURLWithPath: args[i + 2])
    MainActor.assumeIsolated { DevSnapshot.overlay(output: output, background: background) }
    exit(0)
}

if let i = args.firstIndex(of: "--grab"), i + 1 < args.count {
    let folder = URL(fileURLWithPath: args[i + 1])
    Task { @MainActor in
        await DevSnapshot.grab(folder: folder)
        exit(0)
    }
    app.run()
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
