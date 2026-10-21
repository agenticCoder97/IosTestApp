import Foundation

@MainActor
public enum ChapterOrdering {
    public static func comics(_ chapters: [LocalComicChapter]) -> [LocalComicChapter] {
        guard let story = chapters.first?.comicId else { return [] }
        let order = UserDefaults.standard.dictionary(forKey: "reading.chapterOrder." + story.uuidString) as? [String: Int] ?? [:]
        return chapters.sorted {
            let left = order[$0.id.uuidString], right = order[$1.id.uuidString]
            if let left, let right, left != right { return left < right }
            if $0.chapterNumber != $1.chapterNumber { return $0.chapterNumber < $1.chapterNumber }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

public enum BookmarkAnchorStore {
    public static func chapter(for bookmark: UUID) -> UUID? {
        UserDefaults.standard.string(forKey: "reading.bookmarkChapter." + bookmark.uuidString).flatMap(UUID.init(uuidString:))
    }
    public static func save(bookmark: UUID, chapter: UUID) {
        UserDefaults.standard.set(chapter.uuidString, forKey: "reading.bookmarkChapter." + bookmark.uuidString)
    }
}
