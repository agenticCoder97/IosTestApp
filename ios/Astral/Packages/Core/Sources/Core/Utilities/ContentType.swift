import Foundation

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

public enum JobStatus: String, Codable, Sendable {
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
}

public enum FanficSource: String, CaseIterable, Codable, Sendable {
    case ao3
    case ffnet
}

public enum FanficRating: String, CaseIterable, Codable, Sendable {
    case general = "G"
    case teen = "T"
    case mature = "M"
    case explicit = "E"
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
