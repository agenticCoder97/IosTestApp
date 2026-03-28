import Foundation

public struct ComicResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let sourceKey: String
    public let sourceUrl: String
    public let sourceId: String?
    public let thumbnailPath: String?
    public let description: String?
    public let totalChapters: Int
    public let totalPages: Int
    public let language: String?
    public let status: String
    public let authors: [AuthorResponse]?
    public let tags: [TagResponse]?
    public let category: String?
    public let chapters: [ComicChapterResponse]?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct ComicChapterResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let chapterNumber: Double
    public let title: String?
    public let sourceUrl: String?
    public let totalPages: Int
    public let scrapeStatus: String
    public let createdAt: Date
}

public struct PageResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let pageNumber: Int
    public let filePath: String
    public let sourceUrl: String?
    public let widthPx: Int?
    public let heightPx: Int?
}

public struct ComicUpdateRequest: Codable, Sendable {
    public let title: String?
    public let thumbnailPath: String?

    public init(title: String? = nil, thumbnailPath: String? = nil) {
        self.title = title
        self.thumbnailPath = thumbnailPath
    }
}

public struct TagResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let tagType: String
}
