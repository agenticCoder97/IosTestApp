import Foundation

public enum ReadingPositionStore {
    public struct Position: Codable, Sendable {
        public var chapterID: UUID
        public var chapterNumber: Double
        public var page: Int
        public var fraction: Double
        public var offset: Double?
        public var layoutSignature: String?
        public var paragraph: Int
        public init(chapterID: UUID, chapterNumber: Double, page: Int = 0, fraction: Double = 0, paragraph: Int = 0, offset: Double? = nil, layoutSignature: String? = nil) {
            self.chapterID = chapterID; self.chapterNumber = chapterNumber
            self.offset = offset; self.layoutSignature = layoutSignature
            self.page = page; self.fraction = fraction; self.paragraph = paragraph
        }
    }
    private struct StoryState: Codable {
        var lastChapter: UUID
        var chapters: [UUID: Position]
    }
    private static func state(story: UUID) -> StoryState? {
        guard let data = UserDefaults.standard.data(forKey: "reading.positions." + story.uuidString) else { return nil }
        return try? JSONDecoder().decode(StoryState.self, from: data)
    }
    public static func position(story: UUID, chapter: UUID? = nil) -> Position? {
        if let state = state(story: story), let position = state.chapters[chapter ?? state.lastChapter] { return position }
        // Migrate older position records lazily. Prefer the most recent story
        // pointer when it refers to the requested chapter.
        if let data = UserDefaults.standard.data(forKey: "reading.position." + story.uuidString),
           let position = try? JSONDecoder().decode(Position.self, from: data), chapter == nil || position.chapterID == chapter { return position }
        if let chapter, let data = UserDefaults.standard.data(forKey: "reading.position." + chapter.uuidString) {
            return try? JSONDecoder().decode(Position.self, from: data)
        }
        return nil
    }
    public static func save(_ position: Position, story: UUID) {
        var state = state(story: story) ?? StoryState(lastChapter: position.chapterID, chapters: [:])
        state.lastChapter = position.chapterID
        state.chapters[position.chapterID] = position
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: "reading.positions." + story.uuidString)
    }
}
