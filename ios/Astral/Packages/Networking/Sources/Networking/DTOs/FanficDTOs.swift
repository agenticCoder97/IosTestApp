import Foundation

public struct FanficResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let sourceKey: String
    public let sourceUrl: String
    public let sourceId: String?
    public let summary: String?
    public let fandom: String?
    public let relationship: String?
    public let characters: String?
    public let rating: String?
    public let warnings: String?
    public let completionStatus: String
    public let wordCount: Int?
    public let totalChapters: Int
    public let publishedAt: Date?
    public let updatedAtSource: Date?
    public let language: String?
    public let thumbnailPath: String?
    public let authors: [AuthorResponse]?
    public let chapters: [FanficChapterResponse]?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct FanficChapterResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let chapterNumber: Double
    public let title: String?
    public let content: String?
    public let wordCount: Int?
    public let sourceUrl: String?
    public let scrapeStatus: String
    public let createdAt: Date
}
