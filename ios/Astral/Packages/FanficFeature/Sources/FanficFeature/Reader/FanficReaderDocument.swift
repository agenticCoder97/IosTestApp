import Foundation
import SwiftUI
import DesignSystem

/// Prepared once per loaded chapter, never rebuilt by scroll progress updates.
struct FanficReaderDocument: Sendable {
    let paragraphs: [String]
    let wordOffsets: [Int]
    let sceneBreaks: Set<Int>
    let wordCount: Int

    init(text: String) {
        paragraphs = Self.paragraphs(in: text)
        var offsets: [Int] = [], breaks: Set<Int> = [], count = 0
        let markers: Set<String> = ["---", "***", "* * *", "—", "~~~", "- - -", "•••", "⁂", "oOo", "xxx", "XXX"]
        for (index, paragraph) in paragraphs.enumerated() {
            offsets.append(count)
            count += paragraph.split(whereSeparator: \.isWhitespace).count
            if markers.contains(paragraph) || (paragraph.count <= 10 && paragraph.allSatisfy({ "-*~ ".contains($0) })) {
                breaks.insert(index)
            }
        }
        wordOffsets = offsets; sceneBreaks = breaks; wordCount = count
    }

    /// Blank lines separate paragraphs; single line breaks inside one are joined.
    /// Plain-text imports often use Windows line endings or one paragraph per
    /// line, and must not collapse into one block laid out as a single Text.
    static func paragraphs(in text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let clean = { (blocks: [Substring]) in
            blocks.map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
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
    func prepare(_ text: String) -> FanficReaderDocument { FanficReaderDocument(text: text) }
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
