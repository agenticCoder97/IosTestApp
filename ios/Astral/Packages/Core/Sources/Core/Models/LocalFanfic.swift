import Foundation
import SwiftData

@Model
public final class LocalFanfic {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var sourceKey: String
    public var summary: String?
    public var fandom: String?
    public var rating: String?
    public var completionStatus: String
    public var wordCount: Int?
    public var totalChapters: Int
    public var isDownloaded: Bool
    public var lastReadChapterNumber: Int
    /// Fanfic-only: 0.0 to 1.0 scroll position within the current chapter
    public var scrollOffsetPercent: Double?
    public var progressPercent: Double
    public var addedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \LocalFanficChapter.fanfic)
    public var chapters: [LocalFanficChapter]?

    public init(
        id: UUID,
        title: String,
        sourceKey: String,
        summary: String? = nil,
        fandom: String? = nil,
        rating: String? = nil,
        completionStatus: String = "ongoing",
        wordCount: Int? = nil,
        totalChapters: Int = 0,
        isDownloaded: Bool = false,
        lastReadChapterNumber: Int = 0,
        scrollOffsetPercent: Double? = nil,
        progressPercent: Double = 0.0,
        addedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.sourceKey = sourceKey
        self.summary = summary
        self.fandom = fandom
        self.rating = rating
        self.completionStatus = completionStatus
        self.wordCount = wordCount
        self.totalChapters = totalChapters
        self.isDownloaded = isDownloaded
        self.lastReadChapterNumber = lastReadChapterNumber
        self.scrollOffsetPercent = scrollOffsetPercent
        self.progressPercent = progressPercent
        self.addedAt = addedAt
    }
}
