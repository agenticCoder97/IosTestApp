import Foundation
import SwiftData
import Core
import Networking

/// Device adapter for MangaDex's public API. English releases, source chapter UUIDs,
/// no browser cookies, no Astral API. Multiple releases remain visibly distinguished.
@MainActor
enum MangaDexDeviceService {
    static func titleID(_ url: URL?) -> UUID? {
        guard let url, url.scheme == "https", url.host == "mangadex.org" else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "title" else { return nil }
        return UUID(uuidString: String(parts[1]))
    }
    static func importTitle(_ id: UUID, context: ModelContext, onCancel: @escaping () -> Void) async throws -> LocalComic {
        let sourceID = id.uuidString.lowercased()
        let job = LocalScrapeJob(id: UUID(), contentType: "comic", storyId: id, status: "running", sourceUrl: "https://mangadex.org/title/\(sourceID)", sourceKey: "mangadex", jobType: "local-mangadex", currentStep: "Fetching English chapter list", startedAt: .now)
        context.insert(job); try context.save()
        LocalOperationRegistry.shared.register(job.id, cancel: onCancel)
        defer { LocalOperationRegistry.shared.finish(job.id) }
        var didBeginMutation = false
        do {
            let detail: Entity<Manga> = try await MangaDexAPI.shared.get("/manga/\(sourceID)?includes[]=author&includes[]=cover_art")
            var releases: [Chapter] = []; var offset = 0
            while true {
                let feed: Feed = try await MangaDexAPI.shared.get("/manga/\(sourceID)/feed?translatedLanguage[]=en&includes[]=scanlation_group&order[volume]=asc&order[chapter]=asc&order[createdAt]=asc&limit=100&offset=\(offset)&includeExternalUrl=0")
                releases += feed.data.filter { ($0.attributes.pages ?? 0) > 0 && $0.attributes.externalUrl == nil }
                offset += feed.data.count
                if feed.data.isEmpty || offset >= feed.total { break }
            }
            try Task.checkCancellation()
            guard !releases.isEmpty else { throw DeviceError.message("No readable English chapters are available from MangaDex for this title.") }
            // Preserve existing user data; a source refresh only adds/updates metadata.
            try context.save()
            didBeginMutation = true
            let story = try context.fetch(FetchDescriptor<LocalComic>(predicate: #Predicate { $0.id == id })).first
                ?? LocalComic(id: id, title: "", sourceKey: "mangadex-device")
            if story.modelContext == nil { context.insert(story) }
            story.title = detail.data.attributes.title["en"] ?? detail.data.attributes.title.values.sorted().first ?? "MangaDex title"
            story.comicDescription = detail.data.attributes.description["en"]
            UserDefaults.standard.set("https://mangadex.org/title/\(id.uuidString.lowercased())", forKey: "reading.source." + story.id.uuidString)
            story.sourceKey = "mangadex-device"; story.status = "complete"; story.completionStatus = detail.data.attributes.status == "completed" ? "complete" : "ongoing"
            story.totalChapters = releases.count; story.lastSyncedAt = .now
            let existing = try context.fetch(FetchDescriptor<LocalComicChapter>(predicate: #Predicate { $0.comicId == id }))
            for (order, item) in releases.enumerated() {
                let chapter = existing.first { $0.id == item.id } ?? LocalComicChapter(id: item.id, comicId: id, chapterNumber: Double(item.attributes.chapter ?? "") ?? Double(order + 1))
                if chapter.modelContext == nil { context.insert(chapter) }
                chapter.comic = story
                let number = item.attributes.chapter ?? "Special"
                let group = item.relationships?.first(where: { $0.type == "scanlation_group" })?.attributes?.name
                chapter.title = (item.attributes.volume.map { "Vol. " + $0 + " · " } ?? "") + "Ch. \(number)" + (item.attributes.title.map { " · " + $0 } ?? "") + (group.map { " [" + $0 + "]" } ?? "")
                chapter.totalPages = item.attributes.pages ?? 0; chapter.scrapeStatus = "scraped"
            }
            if let author = detail.data.relationships?.first(where: { $0.type == "author" })?.attributes?.name {
                story.authorsJSON = String(data: try JSONEncoder().encode([["name": author]]), encoding: .utf8)
            }
            if let file = detail.data.relationships?.first(where: { $0.type == "cover_art" })?.attributes?.fileName {
                story.thumbnailPath = "https://uploads.mangadex.org/covers/\(id.uuidString.lowercased())/\(file).256.jpg"
            }
            job.status = "completed"; job.currentStep = story.title; job.chaptersScraped = releases.count; job.totalChapters = releases.count; job.completedAt = .now
            try context.save()
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: releases.enumerated().map { ($0.element.id.uuidString, $0.offset) }), forKey: "reading.chapterOrder." + story.id.uuidString)
            return story
        } catch {
            if didBeginMutation { context.rollback() }
            // The job was committed before acquisition began.
            job.status = error is CancellationError ? "cancelled" : "failed"; job.errorMessage = error.localizedDescription; job.completedAt = .now
            try? context.save(); throw error
        }
    }
    static func pages(_ id: UUID) async throws -> [PageResponse] {
        let response: AtHome = try await MangaDexAPI.shared.get("/at-home/server/\(id.uuidString.lowercased())", atHome: true)
        guard let base = URL(string: response.baseUrl), base.scheme == "https", base.host != nil, !response.chapter.data.isEmpty else { throw DeviceError.message("MangaDex did not provide chapter pages.") }
        return response.chapter.data.enumerated().map { index, file in
            PageResponse(id: UUID(), pageNumber: index + 1, filePath: base.appendingPathComponent("data").appendingPathComponent(response.chapter.hash).appendingPathComponent(file).absoluteString)
        }
    }
    struct Entity<T: Decodable & Sendable>: Decodable, Sendable { let data: T }
    struct Manga: Decodable, Sendable { let attributes: Attributes; let relationships: [Relationship]?
        struct Attributes: Decodable, Sendable { let title: [String: String]; let description: [String: String]; let status: String }
    }
    struct Chapter: Decodable, Sendable { let id: UUID; let attributes: Attributes; let relationships: [Relationship]?
        struct Attributes: Decodable, Sendable { let chapter: String?; let volume: String?; let title: String?; let pages: Int?; let externalUrl: String? }
    }
    struct Relationship: Decodable, Sendable { let type: String; let attributes: Attributes?
        struct Attributes: Decodable, Sendable { let name: String?; let fileName: String? }
    }
    struct Feed: Decodable, Sendable { let data: [Chapter]; let total: Int }
    struct AtHome: Decodable, Sendable { let baseUrl: String; let chapter: Images
        struct Images: Decodable, Sendable { let hash: String; let data: [String] }
    }
    enum DeviceError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { text } else { nil } } }
}

/// Serial request slots survive actor reentrancy; rate-limit responses defer future
/// requests and surface to the user instead of spinning retries against the source.
private actor MangaDexAPI {
    static let shared = MangaDexAPI()
    private var nextRequest = Date.distantPast
    private var nextAtHome = Date.distantPast
    func get<T: Decodable & Sendable>(_ path: String, atHome: Bool = false) async throws -> T {
        let now = Date()
        let slot = max(now, nextRequest, atHome ? nextAtHome : now)
        nextRequest = slot.addingTimeInterval(0.3)
        if atHome { nextAtHome = slot.addingTimeInterval(1.6) }
        if slot > now { try await Task.sleep(for: .seconds(slot.timeIntervalSince(now))) }
        try Task.checkCancellation()
        guard let url = URL(string: "https://api.mangadex.org" + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("Astral/1.0 (personal iOS reader)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 429 {
            nextRequest = .now.addingTimeInterval(Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60)
            throw APIError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else { throw APIError.httpError(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
