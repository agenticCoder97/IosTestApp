import Foundation
import SwiftUI

public enum ContentType: String, Codable, Sendable {
    case comic
    case fanfic
}

public enum ScrapeStatus: String, Codable, Sendable {
    case pending
    case scraped
    case failed
}

public enum StoryStatus: String, Codable, Sendable {
    case pending
    case partial
    case complete
}

public enum JobStatus: String, CaseIterable, Codable, Sendable {
    case queued
    case running
    case partial
    case complete
    case failed
}

public enum JobType: String, Codable, Sendable {
    case initial
    case delta
    case retry
}

public enum ComicSource: String, CaseIterable, Codable, Sendable {
    case nhentai
    case toongod
    case hentai20
    case mangadex
    case mangafire
}

public enum FanficSource: String, CaseIterable, Codable, Sendable {
    case ao3
    case ffnet
}

/// Human-readable names for stored source keys, including device-only keys
/// such as `mangadex-device` and `local` that have no enum case.
public enum SourceLabel {
    public static func name(for key: String?) -> String {
        switch key?.lowercased() {
        case "mangadex", "mangadex-device": "MangaDex"
        case "toongod": "ToonGod"
        case "hentai20": "Hentai20"
        case "mangafire": "MangaFire"
        case "nhentai": "nhentai"
        case "ao3": "AO3"
        case "ffnet": "FanFiction.net"
        case "local": "Files"
        case let other?: other.capitalized
        case nil: "Unknown source"
        }
    }
}

public extension ComicSource {
    var displayName: String { SourceLabel.name(for: rawValue) }
}

public extension FanficSource {
    var displayName: String { SourceLabel.name(for: rawValue) }
}

public enum FanficRating: String, CaseIterable, Codable, Sendable {
    case general = "G"
    case teen = "T"
    case mature = "M"
    case explicit = "E"
    case notRated = "NR"
}

public enum CompletionStatus: String, CaseIterable, Codable, Sendable {
    case complete
    case ongoing
    case abandoned
}

public enum ScrollDirection: String, Codable, Sendable {
    case vertical
    case horizontal
}

public enum ReaderBackground: String, CaseIterable, Codable, Sendable {
    case dark
    case sepia
    case paper
}

public enum ReaderFont: String, CaseIterable, Codable, Sendable {
    case system = "System"
    case openSans = "Open Sans"
    case georgia = "Georgia"
    case palatino = "Palatino"
    case courier = "Courier"
    case avenir = "Avenir"

    public func font(size: CGFloat) -> Font {
        switch self {
        case .system: .system(size: size)
        case .openSans: .custom("OpenSans-Regular", size: size)
        case .georgia: .custom("Georgia", size: size)
        case .palatino: .custom("Palatino", size: size)
        case .courier: .custom("Courier", size: size)
        case .avenir: .custom("Avenir", size: size)
        }
    }

    public func boldFont(size: CGFloat) -> Font {
        switch self {
        case .system: .system(size: size, weight: .bold)
        case .openSans: .custom("OpenSans-Bold", size: size)
        case .georgia: .custom("Georgia-Bold", size: size)
        case .palatino: .custom("Palatino-Bold", size: size)
        case .courier: .custom("Courier-Bold", size: size)
        case .avenir: .custom("Avenir-Heavy", size: size)
        }
    }

    public func italicFont(size: CGFloat) -> Font {
        switch self {
        case .system: .system(size: size).italic()
        case .openSans: .custom("OpenSans-Regular", size: size).italic()
        case .georgia: .custom("Georgia-Italic", size: size)
        case .palatino: .custom("Palatino-Italic", size: size)
        case .courier: .custom("Courier-Oblique", size: size)
        case .avenir: .custom("Avenir-Oblique", size: size)
        }
    }
}
