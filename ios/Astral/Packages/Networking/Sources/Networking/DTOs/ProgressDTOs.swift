import Foundation

public struct ComicProgressRequest: Codable, Sendable {
    public let lastChapterNumber: Int
    public let lastPageNumber: Int?

    public init(lastChapterNumber: Int, lastPageNumber: Int? = nil) {
        self.lastChapterNumber = lastChapterNumber
        self.lastPageNumber = lastPageNumber
    }
}

public struct FanficProgressRequest: Codable, Sendable {
    public let lastChapterNumber: Int
    public let scrollOffsetPercent: Double?

    public init(lastChapterNumber: Int, scrollOffsetPercent: Double? = nil) {
        self.lastChapterNumber = lastChapterNumber
        self.scrollOffsetPercent = scrollOffsetPercent
    }
}

public struct ProgressResponse: Codable, Sendable {
    public let id: UUID
    public let contentType: String
    public let storyId: UUID
    public let lastChapterId: UUID?
    public let lastChapterNumber: Int
    public let lastPageNumber: Int?
    public let scrollOffsetPercent: Double?
    public let updatedAt: Date
}
