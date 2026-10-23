import Foundation
import Core

/// Display parts of a source chapter title. MangaDex titles are stored as
/// "Vol. 1 · Ch. 5 · Name [Group]"; other sources often repeat "Chapter 5" in
/// the name. Parsing at display time keeps existing library rows unchanged.
struct ComicChapterLabel {
    let number: String
    let name: String?
    let group: String?
    let volume: String?

    init(_ chapter: LocalComicChapter) {
        number = chapter.chapterNumber.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
        var text = (chapter.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var group: String?
        if text.hasSuffix("]"), let open = text.lastIndex(of: "[") {
            let value = text[text.index(after: open)..<text.index(before: text.endIndex)].trimmingCharacters(in: .whitespaces)
            group = value.isEmpty ? nil : value
            text = String(text[..<open])
        }
        var parts = text.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var volume: String?
        if let first = parts.first, first.hasPrefix("Vol. ") {
            volume = String(first.dropFirst(5)); parts.removeFirst()
        }
        let joined = parts.joined(separator: " · ")
        let stripped = joined.replacingOccurrences(of: #"^(chapter|ch\.?|episode|ep\.?)\s*[\d.]+\s*[:\-–·]?\s*"#,
                                                   with: "", options: [.regularExpression, .caseInsensitive])
        self.name = stripped.isEmpty ? nil : stripped
        self.group = group
        self.volume = volume
    }

    /// "Chapter 5 · Name" for headers.
    var heading: String { "Chapter \(number)" + (name.map { " · " + $0 } ?? "") }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum ComicChapterNavigation {
    /// Adjacent chapter in reading order. Alternate releases of the chapter being
    /// read (same number and name, different group) are skipped, and the same
    /// scanlation group is preferred when the next chapter has several releases.
    /// Distinct chapters that happen to share a number are never skipped.
    @MainActor static func neighbor(of index: Int, in chapters: [LocalComicChapter], forward: Bool) -> Int? {
        guard chapters.indices.contains(index) else { return nil }
        let current = chapters[index]
        let currentName = ComicChapterLabel(current).name
        let step = forward ? 1 : -1
        var candidate = index + step
        while chapters.indices.contains(candidate), chapters[candidate].chapterNumber == current.chapterNumber,
              ComicChapterLabel(chapters[candidate]).name == currentName {
            candidate += step
        }
        guard chapters.indices.contains(candidate) else { return nil }
        guard let group = ComicChapterLabel(current).group else { return candidate }
        let number = chapters[candidate].chapterNumber
        var release = candidate
        while chapters.indices.contains(release), chapters[release].chapterNumber == number {
            if ComicChapterLabel(chapters[release]).group == group { return release }
            release += step
        }
        return candidate
    }
}
