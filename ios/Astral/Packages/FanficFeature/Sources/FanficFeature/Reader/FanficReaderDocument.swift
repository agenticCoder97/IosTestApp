import Foundation
import SwiftUI
import DesignSystem

/// Prepared once per loaded chapter, never rebuilt by scroll progress updates.
struct FanficReaderDocument: Sendable {
    let paragraphs: [String]
    let wordOffsets: [Int]
    let sceneBreaks: Set<Int>
    let wordCount: Int

    /// `keepsLineBreaks` keeps an imported story's intentional line breaks (lists,
    /// poems, messages). Plain-text files are often hard-wrapped, so theirs are joined.
    init(text: String, keepsLineBreaks: Bool = false) {
        paragraphs = Self.paragraphs(in: text, keepsLineBreaks: keepsLineBreaks)
        var offsets: [Int] = [], breaks: Set<Int> = [], count = 0
        let markers: Set<String> = ["---", "***", "* * *", "—", "~~~", "- - -", "•••", "⁂", "oOo", "xxx", "XXX"]
        for (index, paragraph) in paragraphs.enumerated() {
            let plain = FanficTextMarks.plain(paragraph).trimmingCharacters(in: .whitespaces)
            offsets.append(count)
            count += plain.split(whereSeparator: \.isWhitespace).count
            if markers.contains(plain) || (plain.count <= 10 && plain.allSatisfy({ "-*~ ".contains($0) })) {
                breaks.insert(index)
            }
        }
        wordOffsets = offsets; sceneBreaks = breaks; wordCount = count
    }

    /// Blank lines separate paragraphs; single line breaks inside one are joined.
    /// Plain-text imports often use Windows line endings or one paragraph per
    /// line, and must not collapse into one block laid out as a single Text.
    static func paragraphs(in text: String, keepsLineBreaks: Bool = false) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let clean = { (blocks: [Substring]) in
            blocks.map { block in
                // Authors' double spaces after full stops read as gaps in a proportional font.
                block.split(separator: "\n").map { FanficTextMarks.trimmed(String($0)).replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression) }
                    .filter { !$0.isEmpty }
                    .joined(separator: keepsLineBreaks ? "\n" : " ")
            }
            .filter { !FanficTextMarks.plain($0).trimmingCharacters(in: .whitespaces).isEmpty }
        }
        let blocks = clean(normalized.split(separator: /\n[ \t]*\n/))
        guard blocks.count == 1, normalized.contains("\n") else { return blocks }
        return clean(normalized.split(separator: "\n"))
    }

    func paragraphIndex(wordOffset: Int) -> Int {
        guard !paragraphs.isEmpty else { return 0 }
        return wordOffsets.lastIndex(where: { $0 <= wordOffset }) ?? 0
    }
}

actor FanficReaderPreparation {
    static let shared = FanficReaderPreparation()
    func prepare(_ text: String, keepsLineBreaks: Bool) -> FanficReaderDocument { FanficReaderDocument(text: text, keepsLineBreaks: keepsLineBreaks) }
    func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
}

/// High-frequency offsets stay out of the reader's view state and SwiftData model.
@MainActor @Observable final class FanficScrollProgress {
    var percent = 0
    @ObservationIgnored var fraction = 0.0 {
        didSet {
            let value = Int((min(1, max(0, fraction)) * 100).rounded())
            if value != percent { percent = value }
        }
    }
    @ObservationIgnored var offset: Double?
    @ObservationIgnored var paragraph = 0
    @ObservationIgnored var layoutSignature: String?
}

struct FanficProgressReadout: View {
    let progress: FanficScrollProgress
    let chapter: String
    let total: Int
    var body: some View {
        Text("Ch. \(chapter) of \(total) · \(progress.percent)%")
            .font(.footnote).monospacedDigit().foregroundStyle(AstralColors.body)
            .accessibilityLabel("Chapter \(chapter) of \(total), \(progress.percent) percent through the chapter")
    }
}
