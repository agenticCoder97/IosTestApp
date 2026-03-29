import Foundation
import SwiftData

@Model
public final class LocalReadingSession {
    @Attribute(.unique) public var id: UUID
    /// "comic" or "fanfic"
    public var contentType: String
    public var storyId: UUID
    public var startedAt: Date
    public var endedAt: Date?
    /// Number of distinct chapters opened during this session
    public var chaptersRead: Int

    public init(
        id: UUID = UUID(),
        contentType: String,
        storyId: UUID,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        chaptersRead: Int = 1
    ) {
        self.id = id
        self.contentType = contentType
        self.storyId = storyId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.chaptersRead = chaptersRead
    }
}
