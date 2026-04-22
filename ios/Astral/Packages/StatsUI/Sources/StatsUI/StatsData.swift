import Foundation
import Core

// Pure data aggregation — no SwiftUI, no DesignSystem. Keeps the
// render code in SharedStatsView lean and makes this file trivially
// unit-testable.

public struct StatsAggregates {
    public let comics: [LocalComic]
    public let fanfics: [LocalFanfic]
    public let comicChapters: [LocalComicChapter]
    public let sessions: [LocalReadingSession]
    public let bookmarks: [LocalBookmark]

    public init(
        comics: [LocalComic],
        fanfics: [LocalFanfic],
        comicChapters: [LocalComicChapter],
        sessions: [LocalReadingSession],
        bookmarks: [LocalBookmark]
    ) {
        self.comics = comics
        self.fanfics = fanfics
        self.comicChapters = comicChapters
        self.sessions = sessions
        self.bookmarks = bookmarks
    }

    // MARK: — basics (unchanged from the original views)

    public var totalWordsRead: Int {
        fanfics.reduce(0) { $0 + $1.estimatedWordsRead }
    }

    public var totalPagesViewed: Int {
        comics.reduce(0) { total, comic in
            let read = comicChapters.filter {
                $0.comicId == comic.id && $0.chapterNumber <= Double(comic.lastReadChapterNumber)
            }
            return total + read.reduce(0) { $0 + $1.totalPages }
        }
    }

    public var novelEquivalent: Double { Double(totalWordsRead) / 80_000.0 }

    public var totalChaptersRead: Int {
        comics.reduce(0) { $0 + $1.lastReadChapterNumber } +
            fanfics.reduce(0) { $0 + Int($1.lastReadChapterNumber ?? 0) }
    }

    // MARK: — streaks

    public var currentStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: .now)
        let todaySessions = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: checkDate) }
        if todaySessions.isEmpty {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }
        while true {
            let dayStart = checkDate
            let hasSessions = sessions.contains { calendar.isDate($0.startedAt, inSameDayAs: dayStart) }
            if hasSessions {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }
        return streak
    }

    public var longestStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        let calendar = Calendar.current
        let sessionDays = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        let sortedDays = sessionDays.sorted()
        guard !sortedDays.isEmpty else { return 0 }
        var maxStreak = 1
        var current = 1
        for i in 1..<sortedDays.count {
            let diff = calendar.dateComponents([.day], from: sortedDays[i-1], to: sortedDays[i]).day ?? 0
            if diff == 1 {
                current += 1
                maxStreak = max(maxStreak, current)
            } else {
                current = 1
            }
        }
        return maxStreak
    }

    // MARK: — AST-66 reading time

    /// Sessions with a recorded endedAt — partial/crashed sessions excluded.
    public var closedSessions: [LocalReadingSession] {
        sessions.filter { $0.endedAt != nil }
    }

    public var totalReadingSeconds: TimeInterval {
        closedSessions.reduce(0) { sum, s in
            guard let end = s.endedAt else { return sum }
            return sum + max(0, end.timeIntervalSince(s.startedAt))
        }
    }

    public var averageSessionSeconds: TimeInterval {
        let closed = closedSessions
        guard !closed.isEmpty else { return 0 }
        return totalReadingSeconds / Double(closed.count)
    }

    public struct WeeklyMinutes: Identifiable, Equatable {
        public let weekStart: Date
        public let label: String
        public let minutes: Int
        public var id: Date { weekStart }
    }

    public func weeklyReadingMinutes(weeks: Int = 12) -> [WeeklyMinutes] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        let today = calendar.startOfDay(for: .now)
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        return (0..<weeks).reversed().map { weeksAgo in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: currentWeekStart)!
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
            let seconds = closedSessions.filter {
                $0.startedAt >= weekStart && $0.startedAt < weekEnd
            }.reduce(0.0) { sum, s in
                guard let end = s.endedAt else { return sum }
                return sum + max(0, end.timeIntervalSince(s.startedAt))
            }
            return WeeklyMinutes(
                weekStart: weekStart,
                label: formatter.string(from: weekStart),
                minutes: Int(seconds / 60)
            )
        }
    }

    // MARK: — AST-67 tag distribution

    public struct TagCount: Identifiable, Equatable {
        public let tag: String
        public let count: Int
        public var id: String { tag }
    }

    /// Top N tags by frequency. Normalised to lowercase. Reads
    /// `tagsJSON` on comics and fanfics, plus `freeformTags` on fanfics.
    public func topTags(limit: Int = 12) -> [TagCount] {
        var counts: [String: Int] = [:]
        for c in comics { Self.addTags(Self.parseJSONStrings(c.tagsJSON), into: &counts) }
        for f in fanfics {
            Self.addTags(Self.parseJSONStrings(f.tagsJSON), into: &counts)
            Self.addTags(Self.splitCommaList(f.freeformTags), into: &counts)
        }
        return counts
            .sorted { ($0.value, $0.key) > ($1.value, $1.key) }
            .prefix(limit)
            .map { TagCount(tag: $0.key, count: $0.value) }
    }

    private static func parseJSONStrings(_ raw: String?) -> [String] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func splitCommaList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func addTags(_ tags: [String], into counts: inout [String: Int]) {
        for t in tags {
            let key = t.lowercased()
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
    }

    // MARK: — AST-68 heatmap day detail

    public struct DaySessionRow: Identifiable, Equatable {
        public let id: UUID
        public let storyId: UUID
        public let title: String
        public let contentType: String           // "comic" | "fanfic"
        public let chaptersRead: Int
        public let duration: TimeInterval?       // nil if endedAt missing
        public let startedAt: Date
    }

    public func sessionsOn(day: Date) -> [DaySessionRow] {
        let calendar = Calendar.current
        let same = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
        let comicById = Dictionary(uniqueKeysWithValues: comics.map { ($0.id, $0) })
        let fanficById = Dictionary(uniqueKeysWithValues: fanfics.map { ($0.id, $0) })
        return same
            .sorted { $0.startedAt > $1.startedAt }
            .map { s in
                let title: String
                if s.contentType == "comic" {
                    title = comicById[s.storyId]?.title ?? "Unknown comic"
                } else {
                    title = fanficById[s.storyId]?.title ?? "Unknown fanfic"
                }
                let duration = s.endedAt.map { max(0, $0.timeIntervalSince(s.startedAt)) }
                return DaySessionRow(
                    id: s.id,
                    storyId: s.storyId,
                    title: title,
                    contentType: s.contentType,
                    chaptersRead: s.chaptersRead,
                    duration: duration,
                    startedAt: s.startedAt
                )
            }
    }

    // MARK: — AST-69 bookmarks

    public struct BookmarkedStory: Identifiable, Equatable {
        public let storyId: UUID
        public let title: String
        public let contentType: String
        public let count: Int
        public var id: UUID { storyId }
    }

    public var storiesWithBookmarks: Int {
        Set(bookmarks.map { $0.storyId }).count
    }

    public func mostBookmarkedStories(limit: Int = 5) -> [BookmarkedStory] {
        let comicById = Dictionary(uniqueKeysWithValues: comics.map { ($0.id, $0.title) })
        let fanficById = Dictionary(uniqueKeysWithValues: fanfics.map { ($0.id, $0.title) })
        let grouped = Dictionary(grouping: bookmarks, by: { $0.storyId })
        return grouped
            .compactMap { (id, items) -> BookmarkedStory? in
                guard let first = items.first else { return nil }
                let title: String = first.contentType == "comic"
                    ? (comicById[id] ?? "Unknown comic")
                    : (fanficById[id] ?? "Unknown fanfic")
                return BookmarkedStory(
                    storyId: id,
                    title: title,
                    contentType: first.contentType,
                    count: items.count
                )
            }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    public struct WeeklyBookmarks: Identifiable, Equatable {
        public let weekStart: Date
        public let label: String
        public let count: Int
        public var id: Date { weekStart }
    }

    public func weeklyBookmarkActivity(weeks: Int = 12) -> [WeeklyBookmarks] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        let today = calendar.startOfDay(for: .now)
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        return (0..<weeks).reversed().map { weeksAgo in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: currentWeekStart)!
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
            let count = bookmarks.filter {
                $0.createdAt >= weekStart && $0.createdAt < weekEnd
            }.count
            return WeeklyBookmarks(
                weekStart: weekStart,
                label: formatter.string(from: weekStart),
                count: count
            )
        }
    }

    public var topHighlights: [LocalBookmark] {
        bookmarks
            .filter { ($0.selectedText ?? "").isEmpty == false }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20)
            .map { $0 }
    }
}

// MARK: — Duration formatting helpers

public enum StatsFormat {
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func shortDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let rem = m % 60
        return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
    }

    public static func compactNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
