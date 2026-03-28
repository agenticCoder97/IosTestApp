import Foundation
import SwiftData

@Model
public final class LocalScrapeJob {
    @Attribute(.unique) public var id: UUID
    /// "comic" or "fanfic" — discriminator for polymorphic storyId
    public var contentType: String
    /// Logical FK to LocalComic.id or LocalFanfic.id based on contentType.
    /// Not a SwiftData relationship — polymorphic reference resolved at runtime.
    public var storyId: UUID
    public var status: String
    public var chaptersScraped: Int
    public var chaptersFailed: Int
    public var totalChapters: Int?
    public var createdAt: Date
    public var completedAt: Date?
    // Rich fields — populated on creation and synced during polling
    public var sourceUrl: String?
    public var sourceKey: String?
    public var jobType: String?
    public var errorMessage: String?
    public var currentStep: String?
    public var lastErrorType: String?
    public var startedAt: Date?

    public init(
        id: UUID,
        contentType: String,
        storyId: UUID,
        status: String = "queued",
        chaptersScraped: Int = 0,
        chaptersFailed: Int = 0,
        totalChapters: Int? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        sourceUrl: String? = nil,
        sourceKey: String? = nil,
        jobType: String? = nil,
        errorMessage: String? = nil,
        currentStep: String? = nil,
        lastErrorType: String? = nil,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.storyId = storyId
        self.status = status
        self.chaptersScraped = chaptersScraped
        self.chaptersFailed = chaptersFailed
        self.totalChapters = totalChapters
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sourceUrl = sourceUrl
        self.sourceKey = sourceKey
        self.jobType = jobType
        self.errorMessage = errorMessage
        self.currentStep = currentStep
        self.lastErrorType = lastErrorType
        self.startedAt = startedAt
    }
}
