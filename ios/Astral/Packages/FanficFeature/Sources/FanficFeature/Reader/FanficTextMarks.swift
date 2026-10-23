import SwiftUI
import Core

/// Importers keep emphasis and centring as private-use characters in the saved
/// plain text, so copies saved before them still read normally. The reader turns
/// them into styled runs; anything that shows or counts plain text strips them.
enum FanficTextMarks {
    static let italicOpen: Character = "\u{E000}"
    static let italicClose: Character = "\u{E001}"
    static let boldOpen: Character = "\u{E002}"
    static let boldClose: Character = "\u{E003}"
    static let center: Character = "\u{E004}"

    private static let scalars: ClosedRange<UInt32> = 0xE000...0xE004

    static func plain(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { scalars.contains($0.value) }) else { return text }
        return String(text.unicodeScalars.filter { !scalars.contains($0.value) })
    }

    static func isCentered(_ paragraph: String) -> Bool { paragraph.first == center }

    /// Trims a line, including spaces just inside marks at either end
    /// ("  <i> How is it </i>" becomes "<i>How is it</i>").
    static func trimmed(_ line: String) -> String {
        var scalars = Array(line.unicodeScalars)
        func isMark(_ s: Unicode.Scalar) -> Bool { FanficTextMarks.scalars.contains(s.value) }
        func isSpace(_ s: Unicode.Scalar) -> Bool { CharacterSet.whitespaces.contains(s) }
        // Leading: drop spaces before, between and after the opening marks.
        var lead: [Unicode.Scalar] = []
        while let first = scalars.first, isMark(first) || isSpace(first) {
            if isMark(first) { lead.append(first) }
            scalars.removeFirst()
        }
        var trail: [Unicode.Scalar] = []
        while let last = scalars.last, isMark(last) || isSpace(last) {
            if isMark(last) { trail.insert(last, at: 0) }
            scalars.removeLast()
        }
        guard !scalars.isEmpty else { return "" }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: lead); result.append(contentsOf: scalars); result.append(contentsOf: trail)
        return String(result)
    }

    /// Italic and bold runs in the reader's own font family. Unbalanced marks
    /// from damaged markup end at the paragraph instead of leaking further.
    static func styled(_ paragraph: String, font: ReaderFont, size: CGFloat) -> AttributedString {
        var result = AttributedString()
        var italic = 0, bold = 0
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            switch (italic > 0, bold > 0) {
            case (true, true): piece.font = font.boldFont(size: size).italic()
            case (true, false): piece.font = font.italicFont(size: size)
            case (false, true): piece.font = font.boldFont(size: size)
            case (false, false): piece.font = font.font(size: size)
            }
            result += piece
            run = ""
        }
        for character in paragraph {
            switch character {
            case italicOpen: flush(); italic += 1
            case italicClose: flush(); italic = max(0, italic - 1)
            case boldOpen: flush(); bold += 1
            case boldClose: flush(); bold = max(0, bold - 1)
            case center: continue
            default: run.append(character)
            }
        }
        flush()
        return result
    }
}
