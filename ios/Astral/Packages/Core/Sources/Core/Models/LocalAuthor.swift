import Foundation
import SwiftData

@Model
public final class LocalAuthor {
    @Attribute(.unique) public var id: UUID
    public var name: String
    /// Added: missing from architecture doc for consistency with other entity tables
    public var updatedAt: Date

    public init(
        id: UUID,
        name: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
    }
}
