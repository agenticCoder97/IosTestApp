import Foundation
import SwiftData

@Model
public final class UserPreferences {
    @Attribute(.unique) public var id: UUID

    // Comic reader
    public var comicScrollDirection: String

    // Fanfic reader
    public var fanficFontSize: Double
    public var fanficLineHeight: Double
    public var fanficBackground: String

    // Shared reader
    public var readerBrightness: Double

    public init(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        comicScrollDirection: String = "vertical",
        fanficFontSize: Double = 16.0,
        fanficLineHeight: Double = 1.6,
        fanficBackground: String = "dark",
        readerBrightness: Double = 1.0
    ) {
        self.id = id
        self.comicScrollDirection = comicScrollDirection
        self.fanficFontSize = fanficFontSize
        self.fanficLineHeight = fanficLineHeight
        self.fanficBackground = fanficBackground
        self.readerBrightness = readerBrightness
    }
}
