import Foundation
import SwiftData

@Model
public final class LocalFanficChapter {
    @Attribute(.unique) public var id: UUID
    public var fanficId: UUID
    /// Uses Double (not Int) — corrected from architecture doc to match comic chapters.
    /// Supports interlude/bonus chapters like 3.5.
    public var chapterNumber: Double
    public var title: String?
    public var wordCount: Int?
    public var isDownloaded: Bool
    /// Local file path for downloaded chapter text (Documents directory)
    public var localTextPath: String?
    public var scrapeStatus: String
    public var downloadState: String = "none"
    public var downloadedAt: Date?
    public var downloadError: String?

    public var fanfic: LocalFanfic?

    public var downloadStatus: DownloadState {
        get { DownloadState(rawValue: downloadState) ?? .none }
        set { downloadState = newValue.rawValue }
    }

    public init(
        id: UUID,
        fanficId: UUID,
        chapterNumber: Double,
        title: String? = nil,
        wordCount: Int? = nil,
        isDownloaded: Bool = false,
        localTextPath: String? = nil,
        scrapeStatus: String = "pending"
    ) {
        self.id = id
        self.fanficId = fanficId
        self.chapterNumber = chapterNumber
        self.title = title
        self.wordCount = wordCount
        self.isDownloaded = isDownloaded
        self.localTextPath = localTextPath
        self.scrapeStatus = scrapeStatus
    }
}
