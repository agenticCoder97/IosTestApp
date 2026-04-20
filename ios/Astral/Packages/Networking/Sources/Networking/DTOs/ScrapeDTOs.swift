import Foundation

public struct ScrapeRequest: Codable, Sendable {
    public let url: String
    public let sourceKey: String
    public let cookies: [CookieDTO]
    public let userAgent: String
    public let contentType: String
    // AST-30 — MangaDex matcher fields. All optional; ignored on backend
    // for ineligible sources.
    public let pageTitle: String?
    public let skipMatch: Bool
    public let previousSource: String?
    public let previousSourceUrl: String?
    public let matchConfidence: Double?

    public init(
        url: String,
        sourceKey: String,
        cookies: [CookieDTO],
        userAgent: String,
        contentType: String,
        pageTitle: String? = nil,
        skipMatch: Bool = false,
        previousSource: String? = nil,
        previousSourceUrl: String? = nil,
        matchConfidence: Double? = nil
    ) {
        self.url = url
        self.sourceKey = sourceKey
        self.cookies = cookies
        self.userAgent = userAgent
        self.contentType = contentType
        self.pageTitle = pageTitle
        self.skipMatch = skipMatch
        self.previousSource = previousSource
        self.previousSourceUrl = previousSourceUrl
        self.matchConfidence = matchConfidence
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
    public let currentStep: String?
    public let lastErrorType: String?
    public let startedAt: Date?
    public let completedAt: Date?
    public let createdAt: Date
}

public struct ScrapeLogEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let jobId: UUID
    public let timestamp: Date
    public let level: String      // "info" | "warning" | "error"
    public let step: String
    public let message: String
    public let errorType: String?
    public let httpStatus: Int?
    public let durationMs: Int?
    public let chapterNumber: Double?
}

public struct MangaDexMatchPayload: Codable, Sendable, Equatable {
    public let mangaId: String
    public let mangadexUrl: String
    public let title: String
    public let confidence: Double
    public let thumbnailUrl: String?
    public let chapterCount: Int
    public let sourceChapterCount: Int
}

public struct ScrapeMatchResponse: Codable, Sendable {
    public let match: MangaDexMatchPayload
}

public enum ScrapeOutcome: Sendable {
    case jobCreated(ScrapeJobResponse)
    case matchProposed(MangaDexMatchPayload)
}
