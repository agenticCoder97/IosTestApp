import Foundation
import SwiftUI

/// Prepared once per loaded chapter, never rebuilt by scroll progress updates.
struct FanficReaderDocument: Sendable {
    let paragraphs: [String]
    let wordOffsets: [Int]
    let sceneBreaks: Set<Int>
    let wordCount: Int

    init(text: String) {
        paragraphs = text.components(separatedBy: "\n\n").map {
            $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
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
        Text("\(progress.percent)% · Ch. \(chapter) of \(total)")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
}
