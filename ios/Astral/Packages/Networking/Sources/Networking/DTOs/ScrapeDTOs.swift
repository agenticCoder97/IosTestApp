import Foundation

public struct ScrapeRequest: Codable, Sendable {
    public let url: String
    public let sourceKey: String
    public let cookies: [CookieDTO]
    public let userAgent: String
    public let contentType: String

    public init(
        url: String,
        sourceKey: String,
        cookies: [CookieDTO],
        userAgent: String,
        contentType: String
    ) {
        self.url = url
        self.sourceKey = sourceKey
        self.cookies = cookies
        self.userAgent = userAgent
        self.contentType = contentType
    }
}

public struct ScrapeJobResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let contentType: String
    public let storyId: UUID
    public let sourceUrl: String
    public let sourceKey: String
    public let jobType: String
    public let status: String
    public let totalChapters: Int?
    public let chaptersScraped: Int
    public let chaptersFailed: Int
    public let errorMessage: String?
    public let startedAt: Date?
    public let completedAt: Date?
    public let createdAt: Date
}
