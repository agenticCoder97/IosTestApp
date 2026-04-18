import Foundation
import SwiftData

@Model
public final class PendingRemoteDeletion {
    @Attribute(.unique) public var id: UUID
    public var storyId: UUID
    public var contentType: String  // "comic" | "fanfic"
    public var createdAt: Date

    public init(storyId: UUID, contentType: String) {
        self.id = UUID()
        self.storyId = storyId
        self.contentType = contentType
        self.createdAt = .now
    }
}
