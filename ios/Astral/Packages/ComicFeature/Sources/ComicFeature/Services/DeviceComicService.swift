import Foundation
import SwiftData
import WebKit
import CryptoKit
import Core
import Networking
import DesignSystem

/// Browser-session source adapters. Acquisition never calls an Astral server.
@MainActor
enum DeviceComicService {
    static let sources = Set(["nhentai", "toongod", "hentai20"]).union(TappedComicSources.sources)
    private static var loaders: [String: DeviceSourcePageLoader] = [:]
    static func canonical(_ url: URL?, source: String) -> URL? {
        guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        let allowed: [String]
        switch source {
        case "nhentai": allowed = ["nhentai.net", "www.nhentai.net", "nhentai.to", "www.nhentai.to"]
        case "toongod": allowed = ["toongod.org", "www.toongod.org", "toongod.com", "www.toongod.com"]
        case "hentai20": allowed = ["hentai20.io", "www.hentai20.io"]
        case "mangafire": allowed = ["mangafire.to", "www.mangafire.to"]
        default: return nil
        }
        guard allowed.contains(host) else { return nil }
        let parts = url.path.split(separator: "/")
        if source == "nhentai" {
            guard parts.count >= 2, parts[0] == "g", parts[1].allSatisfy(\.isNumber) else { return nil }
            return URL(string: "https://\(host)/g/\(parts[1])/")
        }
        // A chapter page imports its series too.
        if source == "mangafire" {
            guard TappedComicSources.MangaFire.titleID(url) != nil else { return nil }
            return URL(string: "https://\(host)/title/\(parts[1])")
        }
        guard parts.count >= 2, ["manga", "webtoon"].contains(String(parts[0])) else { return nil }
        return URL(string: "https://\(host)/\(parts[0])/\(parts[1])/")
    }
    static func importTitle(from browser: WKWebView, source: String, context: ModelContext, onCancel: @escaping () -> Void) async throws -> LocalComic {
        guard let url = canonical(browser.url, source: source), !browser.isLoading else { throw SourceError.message("Open a series/gallery page in Add and wait for it to load.") }
        let known = try context.fetch(FetchDescriptor<LocalComic>()).first { $0.sourceKey == source && UserDefaults.standard.string(forKey: "reading.source." + $0.id.uuidString).flatMap(URL.init(string:))?.path == url.path }
        let id = known?.id ?? stableID(source + ":" + url.path)
        let job = LocalScrapeJob(id: UUID(), contentType: "comic", storyId: id, status: "running", sourceUrl: url.absoluteString, sourceKey: source, jobType: "local-comic-import", currentStep: "Reading series metadata", startedAt: .now)
        context.insert(job); try context.save()
        LocalOperationRegistry.shared.register(job.id, cancel: onCancel)
        defer { LocalOperationRegistry.shared.finish(job.id) }
        var mutating = false
        do {
            await synchronizeCookies()
            if let ua = try? await browser.evaluateJavaScript("navigator.userAgent") as? String { UserDefaults.standard.set(ua, forKey: "reading.sourceUserAgent." + source) }
            let work: Work? = TappedComicSources.sources.contains(source)
                ? try await TappedComicSources.work(url: url, source: source, loader: loader(for: source))
                : try await extract(browser, url: url, source: source, mode: "import").work
            guard let work, !work.title.isEmpty, !work.chapters.isEmpty, work.chapters.count <= 10000 else { throw SourceError.message("The source returned an incomplete chapter list.") }
            try Task.checkCancellation()
            guard !job.isDeleted else { throw CancellationError() }
            try context.save(); mutating = true
            let comic = known ?? LocalComic(id: id, title: work.title, sourceKey: source)
            if comic.modelContext == nil { context.insert(comic) }
            comic.title = work.title; comic.comicDescription = work.description
            // A page without a cover keeps the one already saved. Imports before the
            // importer fix stored ".../undefined", which never loads.
            if let cover = work.cover { comic.thumbnailPath = cover }
            else if comic.thumbnailPath?.hasSuffix("/undefined") == true { comic.thumbnailPath = nil }
            comic.authorsJSON = String(data: try JSONEncoder().encode(work.authors.map { ["name": $0] }), encoding: .utf8)
            comic.tagsJSON = String(data: try JSONEncoder().encode(work.tags), encoding: .utf8)
            comic.status = "complete"; comic.totalChapters = work.chapters.count; comic.lastSyncedAt = .now
            if known == nil { comic.seenTotalChapters = work.chapters.count }
            let existing = try context.fetch(FetchDescriptor<LocalComicChapter>(predicate: #Predicate { $0.comicId == id }))
            var ordered: [String: Int] = [:]
            for (index, item) in work.chapters.enumerated() {
                guard let chapterURL = URL(string: item.url), chapterURL.scheme == "https", chapterURL.host == url.host else { throw SourceError.message("The source returned an invalid chapter link.") }
                let chapterID = existing.first(where: { UserDefaults.standard.string(forKey: "reading.chapterSource." + $0.id.uuidString).flatMap(URL.init(string:))?.path == URL(string: item.url)?.path })?.id ?? stableID(source + ":" + (URL(string: item.url)?.path ?? item.url))
                let chapter = existing.first(where: { $0.id == chapterID }) ?? LocalComicChapter(id: chapterID, comicId: id, chapterNumber: item.number)
                if chapter.modelContext == nil { context.insert(chapter) }
                chapter.comic = comic; chapter.chapterNumber = item.number; chapter.title = item.title; chapter.scrapeStatus = "scraped"
                if !item.pages.isEmpty { chapter.totalPages = item.pages.count }
                ordered[chapterID.uuidString] = index
            }
            job.status = "completed"; job.currentStep = comic.title; job.chaptersScraped = work.chapters.count; job.totalChapters = work.chapters.count; job.completedAt = .now
            try context.save()
            UserDefaults.standard.set(url.absoluteString, forKey: "reading.source." + id.uuidString)
            UserDefaults.standard.set(ordered, forKey: "reading.chapterOrder." + id.uuidString)
            for item in work.chapters {
                let chapterID = existing.first(where: { UserDefaults.standard.string(forKey: "reading.chapterSource." + $0.id.uuidString).flatMap(URL.init(string:))?.path == URL(string: item.url)?.path })?.id ?? stableID(source + ":" + (URL(string: item.url)?.path ?? item.url))
                UserDefaults.standard.set(item.url, forKey: "reading.chapterSource." + chapterID.uuidString)
                if !item.pages.isEmpty { try? saveManifest(item.pages, comic: id, chapter: chapterID) }
                else { try? FileManager.default.removeItem(at: manifestURL(comic: id, chapter: chapterID)) }
            }
            return comic
        } catch {
            if mutating { context.rollback() }
            if !job.isDeleted { job.status = error is CancellationError ? "cancelled" : "failed"; job.errorMessage = error.localizedDescription; job.completedAt = .now; try? context.save() }
            throw error
        }
    }
    static func pages(comic: LocalComic, chapter: LocalComicChapter) async throws -> [PageResponse] {
        await synchronizeCookies()
        let manifest = manifestURL(comic: comic.id, chapter: chapter.id)
        if let data = try? Data(contentsOf: manifest), let urls = try? JSONDecoder().decode([String].self, from: data), !urls.isEmpty {
            return try pageResponses(urls)
        }
        guard sources.contains(comic.sourceKey), let sourceURL = UserDefaults.standard.string(forKey: "reading.chapterSource." + chapter.id.uuidString).flatMap(URL.init(string:)) else {
            throw SourceError.message("Open this comic's source in Add and import it to reconnect its chapter links. Saved pages remain readable.")
        }
        let loader = loader(for: comic.sourceKey)
        try await Task.sleep(for: .seconds(1))
        let urls: [String]
        if TappedComicSources.sources.contains(comic.sourceKey) {
            urls = try await TappedComicSources.pages(chapterURL: sourceURL, source: comic.sourceKey, loader: loader)
        } else {
            try await loader.load(sourceURL)
            urls = try await extract(loader.webView, url: sourceURL, source: comic.sourceKey, mode: "pages").pages ?? []
        }
        guard !urls.isEmpty else { throw SourceError.message("No pages were returned. Open the chapter in Add, then retry.") }
        let result = try pageResponses(urls)
        try saveManifest(urls, comic: comic.id, chapter: chapter.id)
        return result
    }
    private static func loader(for source: String) -> DeviceSourcePageLoader {
        if let loader = loaders[source] { return loader }
        let loader = DeviceSourcePageLoader()
        loaders[source] = loader
        return loader
    }
    static func imageRequest(_ url: URL, comic: UUID, chapter: UUID) -> URLRequest {
        let referrer = UserDefaults.standard.string(forKey: "reading.chapterSource." + chapter.uuidString) ?? UserDefaults.standard.string(forKey: "reading.source." + comic.uuidString)
        return SourceImageTransport.request(url, referrer: referrer)
    }
    private static func synchronizeCookies() async {
        for cookie in await WKWebsiteDataStore.default().httpCookieStore.allCookies() { HTTPCookieStorage.shared.setCookie(cookie) }
    }
    private static func pageResponses(_ urls: [String]) throws -> [PageResponse] {
        guard urls.count <= 3000, urls.allSatisfy({ URL(string: $0)?.scheme == "https" }) else { throw SourceError.message("The source returned an invalid page list.") }
        return urls.enumerated().map { PageResponse(id: stableID($0.element), pageNumber: $0.offset + 1, filePath: $0.element) }
    }
    private static func extract(_ browser: WKWebView, url: URL, source: String, mode: String) async throws -> Response {
        guard let file = Bundle.module.url(forResource: "ComicSourceImport", withExtension: "js") else { throw SourceError.message("The source importer is missing.") }
        let script = try String(contentsOf: file, encoding: .utf8)
        let value = try await browser.callAsyncJavaScript(script, arguments: ["targetURL": url.absoluteString, "sourceKey": source, "mode": mode], in: nil, contentWorld: .defaultClient)
        try Task.checkCancellation()
        guard let json = value as? String, let data = json.data(using: .utf8) else { throw SourceError.message("The source returned unreadable data.") }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let message = response.error { throw SourceError.message(message) }
        return response
    }
    private static func manifestURL(comic: UUID, chapter: UUID) -> URL { .documentsDirectory.appendingPathComponent("comicSources/\(comic)/\(chapter).json") }
    private static func saveManifest(_ urls: [String], comic: UUID, chapter: UUID) throws {
        _ = try pageResponses(urls)
        let path = manifestURL(comic: comic, chapter: chapter)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(urls).write(to: path, options: .atomic)
    }
    private static func stableID(_ text: String) -> UUID {
        let hex = SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        let chars = Array(hex); let parts = [0..<8,8..<12,12..<16,16..<20,20..<32].map { String(chars[$0]) }
        return UUID(uuidString: parts.joined(separator: "-"))!
    }
    struct Response: Decodable { let error: String?; let work: Work?; let pages: [String]? }
    struct Work: Decodable { let title: String; let description: String; let authors: [String]; let tags: [[String:String]]; let cover: String?; let chapters: [Chapter] }
    struct Chapter: Decodable { let url: String; let number: Double; let title: String; let pages: [String] }
    enum SourceError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { text } else { nil } } }
}
