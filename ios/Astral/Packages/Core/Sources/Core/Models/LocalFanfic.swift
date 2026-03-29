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

    // MARK: - Feature fields (additive — all optional/defaulted for migration safety)

    /// Whether the user has starred this fanfic as a favourite.
    public var isFavorite: Bool
    /// Tracks the totalChapters count the user last saw, enabling new-chapter badges.
    public var seenTotalChapters: Int
    /// Updated when the user opens the detail view; drives "Continue Reading" sort order.
    public var lastReadAt: Date?

    /// Thumbnail image path (generic placeholder for fanfics)
    public var thumbnailPath: String?
    /// Characters in the story
    public var characters: String?
    /// Relationship/pairing
    public var pairing: String?
    /// Content warnings
    public var warnings: String?
    /// Date the story was first published
    public var publishedAt: Date?
    /// Date the story was last updated at source
    public var updatedAtSource: Date?
    /// JSON-encoded array of tag dicts from API
    public var tagsJSON: String?
    /// Date when the user first completed this fanfic (progressPercent reached 1.0)
    public var completedAt: Date?

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
        addedAt: Date = .now,
        isFavorite: Bool = false,
        seenTotalChapters: Int = 0,
        lastReadAt: Date? = nil
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
        self.isFavorite = isFavorite
        self.seenTotalChapters = seenTotalChapters
        self.lastReadAt = lastReadAt
    }

    /// Number of chapters added since the user last viewed the detail screen.
    public var newChapterCount: Int {
        max(0, totalChapters - seenTotalChapters)
    }

    /// Estimated words read based on progress and total word count.
    public var estimatedWordsRead: Int {
        guard let wc = wordCount, totalChapters > 0 else { return 0 }
        return Int(Double(wc) * progressPercent)
    }
}
