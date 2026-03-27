import Foundation
import SwiftData

@Model
public final class LocalComic {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var sourceKey: String
    public var thumbnailPath: String?
    public var totalChapters: Int
    public var status: String
    public var isDownloaded: Bool
    public var lastReadChapterNumber: Int
    public var progressPercent: Double
    public var addedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \LocalComicChapter.comic)
    public var chapters: [LocalComicChapter]?

    public init(
        id: UUID,
        title: String,
        sourceKey: String,
        thumbnailPath: String? = nil,
        totalChapters: Int = 0,
        status: String = "pending",
        isDownloaded: Bool = false,
        lastReadChapterNumber: Int = 0,
        progressPercent: Double = 0.0,
        addedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.sourceKey = sourceKey
        self.thumbnailPath = thumbnailPath
        self.totalChapters = totalChapters
        self.status = status
        self.isDownloaded = isDownloaded
        self.lastReadChapterNumber = lastReadChapterNumber
        self.progressPercent = progressPercent
        self.addedAt = addedAt
    }
}
