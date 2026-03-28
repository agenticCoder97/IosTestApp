import Foundation
import SwiftData

@Model
public final class LocalComic {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var sourceKey: String
    public var thumbnailPath: String?
    public var comicDescription: String?
    public var totalChapters: Int
    public var status: String
    public var isDownloaded: Bool
    public var lastReadChapterNumber: Int
    public var progressPercent: Double
    public var addedAt: Date

    // MARK: - Feature fields (additive — all optional/defaulted for migration safety)

    /// Whether the user has starred this comic as a favourite.
    public var isFavorite: Bool
    /// Tracks the totalChapters count the user last saw, enabling new-chapter badges.
    /// Set equal to totalChapters on first insert; badge = totalChapters - seenTotalChapters.
    public var seenTotalChapters: Int
    /// Updated when the user opens the detail view; drives "Continue Reading" sort order.
    public var lastReadAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \LocalComicChapter.comic)
    public var chapters: [LocalComicChapter]?

    public init(
        id: UUID,
        title: String,
        sourceKey: String,
        thumbnailPath: String? = nil,
        comicDescription: String? = nil,
        totalChapters: Int = 0,
        status: String = "pending",
        isDownloaded: Bool = false,
        lastReadChapterNumber: Int = 0,
        progressPercent: Double = 0.0,
        addedAt: Date = .now,
        isFavorite: Bool = false,
        seenTotalChapters: Int = 0,
        lastReadAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceKey = sourceKey
        self.thumbnailPath = thumbnailPath
        self.comicDescription = comicDescription
        self.totalChapters = totalChapters
        self.status = status
        self.isDownloaded = isDownloaded
        self.lastReadChapterNumber = lastReadChapterNumber
        self.progressPercent = progressPercent
        self.addedAt = addedAt
        self.isFavorite = isFavorite
        self.seenTotalChapters = seenTotalChapters
        self.lastReadAt = lastReadAt
    }

    /// Number of chapters added since the user last viewed the detail screen.
    public var newChapterCount: Int {
        max(0, totalChapters - seenTotalChapters)
    }
}
