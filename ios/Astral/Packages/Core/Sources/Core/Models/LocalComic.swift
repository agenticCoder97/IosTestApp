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

    /// Story completion status: "ongoing", "complete", or "abandoned". nil = unknown.
    public var completionStatus: String? = nil

    /// nhentai category (nullable)
    public var category: String?
    /// JSON-encoded array of {name, tag_type} dicts from API
    public var tagsJSON: String?
    /// JSON-encoded array of {id, name} dicts from API
    public var authorsJSON: String?
    /// Number of initial pages to skip per chapter (e.g. credit pages in webtoons)
    public var skipFirstNPages: Int
    /// Page number within the current chapter (1-based) — for resume-at-page
    public var lastReadPageNumber: Int
    /// Date when the user first completed this comic (progressPercent reached 1.0)
    public var completedAt: Date?
    /// Archive status: none, archiving, archived, unarchiving
    public var archiveStatus: String?
    /// When the comic was archived
    public var archivedAt: Date?
    /// Last time the comic metadata was synced from the backend
    public var lastSyncedAt: Date?

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
        lastReadAt: Date? = nil,
        skipFirstNPages: Int = 0
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
        self.skipFirstNPages = skipFirstNPages
        self.lastReadPageNumber = 0
    }

    /// Number of chapters added since the user last viewed the detail screen.
    public var newChapterCount: Int {
        max(0, totalChapters - seenTotalChapters)
    }

    public var isArchived: Bool { archiveStatus == "archived" }
    public var isArchiving: Bool { archiveStatus == "archiving" }
    public var isUnarchiving: Bool { archiveStatus == "unarchiving" }

    public var isFullyDownloaded: Bool {
        guard let chs = chapters, !chs.isEmpty else { return false }
        return chs.allSatisfy { $0.downloadStatus == .complete }
    }
}
