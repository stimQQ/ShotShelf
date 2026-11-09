import Foundation
import Vision

enum OCR {
    static func recognize(_ url: URL, priority: TaskPriority = .userInitiated) async -> String {
        await Task.detached(priority: priority) { text(from: url) }.value
    }

    /// On-device text recognition with Apple Vision (offline).
    ///
    /// With Chinese listed first, Vision turns ASCII punctuation in code/English into full-width
    /// forms and misreads some Latin words; with English first it drops Chinese entirely.
    /// So: recognize as Chinese, and if no CJK came back, redo the pass as English.
    static func text(from url: URL) -> String {
        let text = compose(observations(url, languages: ["zh-Hans", "zh-Hant", "en-US"]))
        if !text.isEmpty && !containsIdeographs(text) {
            let latin = compose(observations(url, languages: ["en-US"]))
            if !latin.isEmpty { return latin }
        }
        // Mixed screenshots: lines without any CJK get half-width punctuation back.
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { containsIdeographs(String($0)) ? String($0) : halfWidth(String($0)) }
            .joined(separator: "\n")
    }

    private static func observations(_ url: URL, languages: [String]) -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(url: url, options: [:]).perform([request])
        } catch {
            return []
        }
        return request.results ?? []
    }

    private static func containsIdeographs(_ text: String) -> Bool {
        text.unicodeScalars.contains { s in
            (0x3400...0x9FFF).contains(s.value)      // CJK ideographs
                || (0x3040...0x30FF).contains(s.value) // kana
                || (0xAC00...0xD7AF).contains(s.value) // hangul
        }
    }

    private static func halfWidth(_ line: String) -> String {
        var scalars = String.UnicodeScalarView()
        for s in line.unicodeScalars {
            if (0xFF01...0xFF5E).contains(s.value), let ascii = Unicode.Scalar(s.value - 0xFEE0) {
                scalars.append(ascii)
            } else if s.value == 0x3000 {
                scalars.append(" ")
            } else {
                scalars.append(s)
            }
        }
        return String(scalars)
    }

    /// Rebuild reading order: group boxes into lines top-to-bottom, then left-to-right.
    private static func compose(_ observations: [VNRecognizedTextObservation]) -> String {
        struct Piece { let text: String; let box: CGRect }
        let pieces = observations
            .compactMap { obs -> Piece? in
                guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                return Piece(text: text, box: obs.boundingBox)
            }
            .sorted { $0.box.midY > $1.box.midY } // Vision's origin is bottom-left

        var lines: [[Piece]] = []
        for piece in pieces {
            if let anchor = lines.last?.first,
               abs(anchor.box.midY - piece.box.midY) < min(anchor.box.height, piece.box.height) * 0.5 {
                lines[lines.count - 1].append(piece)
            } else {
                lines.append([piece])
            }
        }

        return lines.map { line in
            line.sorted { $0.box.minX < $1.box.minX }
                .map(\.text)
                .reduce("") { joined, next in
                    guard let last = joined.last, let first = next.first else { return joined + next }
                    return joined + (isCJK(last) || isCJK(first) ? "" : " ") + next
                }
        }
        .joined(separator: "\n")
    }

    private static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains { s in
            (0x3000...0x9FFF).contains(s.value) || (0xFF00...0xFFEF).contains(s.value)
        }
    }
}
