import Foundation
import SwiftData

/// A user-saved bookmark within a comic chapter or fanfic chapter.
/// Stored locally only — never synced to backend.
@Model
public final class LocalBookmark {
    @Attribute(.unique) public var id: UUID
    /// "comic" or "fanfic"
    public var contentType: String
    public var storyId: UUID
    public var chapterNumber: Double
    /// Page number for comics; nil for fanfics.
    public var pageNumber: Int?
    /// Scroll position (0–1) for fanfics; nil for comics.
    public var scrollPercent: Double?
    /// Optional user note attached to the bookmark.
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        contentType: String,
        storyId: UUID,
        chapterNumber: Double,
        pageNumber: Int? = nil,
        scrollPercent: Double? = nil,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.contentType = contentType
        self.storyId = storyId
        self.chapterNumber = chapterNumber
        self.pageNumber = pageNumber
        self.scrollPercent = scrollPercent
        self.note = note
        self.createdAt = createdAt
    }

    /// Human-readable label for display in bookmark lists.
    public var displayLabel: String {
        let chStr = chapterNumber.truncatingRemainder(dividingBy: 1) == 0
            ? "Ch. \(Int(chapterNumber))"
            : "Ch. \(chapterNumber)"
        if let page = pageNumber {
            return "\(chStr), Page \(page)"
        }
        if let pct = scrollPercent {
            return "\(chStr) — \(Int(pct * 100))%"
        }
        return chStr
    }
}
