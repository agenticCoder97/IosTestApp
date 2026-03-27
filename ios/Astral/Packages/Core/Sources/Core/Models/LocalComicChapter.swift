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

    public var comic: LocalComic?

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
