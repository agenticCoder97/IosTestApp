import Foundation
import SwiftData

@Model
public final class LocalComicChapter {
    @Attribute(.unique) public var id: UUID
    public var comicId: UUID
    public var chapterNumber: Double
    public var title: String?
    public var totalPages: Int
    public var isDownloaded: Bool
    public var scrapeStatus: String
    /// Local directory path for downloaded page images (Documents directory)
    public var localPagesPath: String?
    public var downloadState: String = "none"
    public var downloadedAt: Date?
    public var downloadSizeBytes: Int64?
    public var downloadError: String?

    public var comic: LocalComic?

    public var downloadStatus: DownloadState {
        get { DownloadState(rawValue: downloadState) ?? .none }
        set { downloadState = newValue.rawValue }
    }

    public init(
        id: UUID,
        comicId: UUID,
        chapterNumber: Double,
        title: String? = nil,
        totalPages: Int = 0,
        isDownloaded: Bool = false,
        scrapeStatus: String = "pending"
    ) {
        self.id = id
        self.comicId = comicId
        self.chapterNumber = chapterNumber
        self.title = title
        self.totalPages = totalPages
        self.isDownloaded = isDownloaded
        self.scrapeStatus = scrapeStatus
    }
}
