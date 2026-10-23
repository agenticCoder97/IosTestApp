import Foundation
import SwiftData
import UIKit
import WebKit
import Core
import Networking
import DesignSystem

/// Imports an AO3 work using the browser's own session, then stores the same
/// text files the existing reader uses. No Astral API requests are involved.
@MainActor
final class AO3ImportService {
    static let shared = AO3ImportService()
    private var activeImports: Set<URL> = []

    static func workURL(from url: URL?) -> URL? {
        guard let url, url.scheme == "https",
              url.host?.lowercased() == "archiveofourown.org" else { return nil }
        // Works opened from a collection live at /collections/<name>/works/<id>.
        let path = url.path.split(separator: "/")
        let parts = path.first == "collections" && path.count >= 4 ? Array(path.dropFirst(2)) : Array(path)
        guard parts.count >= 2, parts[0] == "works",
              !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://archiveofourown.org/works/\(parts[1])")
    }
    static func ffnetURL(from url: URL?) -> URL? {
        guard let url, url.scheme == "https", ["www.fanfiction.net", "m.fanfiction.net", "fanfiction.net"].contains(url.host?.lowercased() ?? "") else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "s", parts[1].allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://www.fanfiction.net/s/\(parts[1])/1/")
    }

    func importWork(from webView: WKWebView, modelContext: ModelContext, onCancel: @escaping () -> Void = {}) async throws -> LocalFanfic {
        let source = Self.ffnetURL(from: webView.url) == nil ? "ao3" : "ffnet"
        let canonical = Self.workURL(from: webView.url) ?? Self.ffnetURL(from: webView.url)
        let existing = try modelContext.fetch(FetchDescriptor<LocalFanfic>()).first { $0.sourceKey == source && $0.sourceUrl.flatMap(URL.init(string:)).map { (Self.workURL(from: $0) ?? Self.ffnetURL(from: $0)) == canonical } == true }
        let job = LocalScrapeJob(id: UUID(), contentType: "fanfic", storyId: existing?.id ?? UUID(), status: "running",
            sourceUrl: canonical?.absoluteString, sourceKey: source, jobType: "local-" + source, currentStep: "Fetching the complete work", startedAt: .now)
        modelContext.insert(job)
        try modelContext.save()
        LocalOperationRegistry.shared.register(job.id, cancel: onCancel)
        defer { LocalOperationRegistry.shared.finish(job.id) }
        do {
            let work = try await importContents(from: webView, modelContext: modelContext)
            job.storyId = work.id; job.status = "completed"; job.currentStep = work.title
            job.totalChapters = work.totalChapters; job.chaptersScraped = work.totalChapters; job.completedAt = .now
            try modelContext.save()
            return work
        } catch {
            if let partial = error as? FFNetPartialImport {
                job.storyId = partial.storyID; job.chaptersScraped = partial.saved; job.totalChapters = partial.expected
            }
            job.status = error is CancellationError ? "cancelled" : "failed"
            job.errorMessage = error is CancellationError ? "Import cancelled. Saved content was retained." : error.localizedDescription
            job.completedAt = .now
            try? modelContext.save()
            throw error
        }
    }

    private func importContents(from webView: WKWebView, modelContext: ModelContext) async throws -> LocalFanfic {
        guard let canonicalURL = Self.workURL(from: webView.url) ?? Self.ffnetURL(from: webView.url), !webView.isLoading else {
            throw AO3ImportError("Open an AO3 or FFNet story and wait for it to finish loading before importing.")
        }
        guard activeImports.insert(canonicalURL).inserted else {
            throw AO3ImportError("This work is already being imported.")
        }
        defer { activeImports.remove(canonicalURL) }
        let sourceKey = Self.ffnetURL(from: canonicalURL) == nil ? "ao3" : "ffnet"
        let fullURL = sourceKey == "ffnet" ? canonicalURL : canonicalURL.appending(queryItems: [
            URLQueryItem(name: "view_full_work", value: "true"),
            URLQueryItem(name: "view_adult", value: "true")
        ])
        guard let scriptURL = Bundle.module.url(forResource: sourceKey == "ffnet" ? "FFNetImport" : "AO3Import", withExtension: "js") else {
            throw AO3ImportError("The source importer could not be loaded.")
        }
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let response: AO3ImportResponse
        if sourceKey == "ffnet" {
            do {
                response = try await readFFNet(script: script, browser: webView, canonical: canonicalURL, context: modelContext)
            } catch let stopped as FFNetStopped {
                // Keep what arrived: the story and its first chapters go into the
                // library, and importing again continues from the checkpoint.
                let story = try await commit(stopped.work, sourceKey: sourceKey, canonicalURL: canonicalURL,
                                             expectedChapters: stopped.expected, modelContext: modelContext)
                if let page = stopped.verificationPage { webView.load(URLRequest(url: page)) }
                throw FFNetPartialImport(storyID: story.id, saved: stopped.work.chapters.count, expected: stopped.expected,
                                         reason: stopped.reason, needsVerification: stopped.verificationPage != nil)
            }
        } else {
            let result = try await webView.callAsyncJavaScript(script, arguments: ["workURL": fullURL.absoluteString], in: nil, contentWorld: .defaultClient)
            try Task.checkCancellation()
            guard let json = result as? String, let data = json.data(using: .utf8) else { throw AO3ImportError("The source returned an unreadable work. Reload the page and try again.") }
            response = try JSONDecoder().decode(AO3ImportResponse.self, from: data)
        }
        if let error = response.error {
            if ["verification", "login", "incomplete"].contains(error) {
                // Put the actual full-work page in front of the user so a
                // challenge/login can be completed in this same session.
                webView.load(URLRequest(url: fullURL))
            }
            throw AO3ImportError.message(for: error)
        }
        guard let work = response.work else { throw AO3ImportError.message(for: "incomplete") }
        return try await commit(work, sourceKey: sourceKey, canonicalURL: canonicalURL, expectedChapters: nil, modelContext: modelContext)
    }

    /// Writes a fetched work into the library. When fewer chapters arrived than
    /// `expectedChapters`, this is a partial FFNet import: chapters not fetched yet
    /// are left alone rather than marked removed, and the checkpoint is kept.
    private func commit(_ work: AO3WorkImport, sourceKey: String, canonicalURL: URL, expectedChapters: Int?,
                        modelContext: ModelContext) async throws -> LocalFanfic {
        guard !work.title.isEmpty, !work.chapters.isEmpty,
              work.chapters.allSatisfy({ !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw AO3ImportError.message(for: "incomplete")
        }
        let partial = (expectedChapters ?? 0) > work.chapters.count

        let existing = try modelContext.fetch(FetchDescriptor<LocalFanfic>(
            predicate: #Predicate { $0.sourceKey == sourceKey }
        )).first { (Self.workURL(from: $0.sourceUrl.flatMap(URL.init(string:))) ?? Self.ffnetURL(from: $0.sourceUrl.flatMap(URL.init(string:)))) == canonicalURL }
        let fanficID = existing?.id ?? UUID()
        let oldChapters = try modelContext.fetch(FetchDescriptor<LocalFanficChapter>(
            predicate: #Predicate { $0.fanficId == fanficID }
        ))
        let mappingKey = "reading." + sourceKey + ".sources." + fanficID.uuidString
        let oldMapping = UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
        var newMapping = oldMapping
        let bookmarks = try modelContext.fetch(FetchDescriptor<LocalBookmark>(predicate: #Predicate { $0.storyId == fanficID }))
        let bookmarkChapters = bookmarks.map { bookmark in (bookmark, oldChapters.first { $0.chapterNumber == bookmark.chapterNumber }?.id) }
        let lastChapterID = oldChapters.first { $0.chapterNumber == existing?.lastReadChapterNumber }?.id
        var usedIDs = Set<UUID>()
        var replacedPaths: [String] = []
        let importID = UUID()
        let paths = try await AO3ImportStorage.shared.write(work.chapters, fanficID: fanficID, importID: importID)
        do {
            try Task.checkCancellation()
            if existing?.isDeleted == true { throw CancellationError() }
            // Save pre-existing UI edits before beginning the import. There
            // are no suspension points between mutation and save/rollback.
            try modelContext.save()
        } catch {
            await AO3ImportStorage.shared.remove(paths)
            throw error
        }

        let fanfic = existing ?? LocalFanfic(id: fanficID, title: work.title, sourceKey: sourceKey)
        do {
            if existing == nil { modelContext.insert(fanfic) }
            fanfic.title = work.title
            fanfic.sourceUrl = canonicalURL.absoluteString
            fanfic.summary = work.summary
            fanfic.authorsText = work.authors.joined(separator: ", ")
            fanfic.fandom = work.fandom
            fanfic.rating = work.rating
            fanfic.characters = work.characters
            fanfic.pairing = work.pairing
            fanfic.warnings = work.warnings
            fanfic.freeformTags = work.freeformTags
            fanfic.wordCount = work.wordCount
            fanfic.completionStatus = work.complete ? "complete" : "ongoing"
            fanfic.totalChapters = max(expectedChapters ?? 0, work.chapters.count)
            fanfic.publishedAt = Self.date(work.publishedAt)
            fanfic.updatedAtSource = Self.date(work.updatedAt)
            fanfic.hits = work.hits
            fanfic.kudos = work.kudos
            fanfic.commentsCount = work.commentsCount
            fanfic.bookmarksCount = work.bookmarksCount
            fanfic.lastSyncedAt = .now
            fanfic.isDownloaded = !partial
            if existing == nil { fanfic.seenTotalChapters = fanfic.totalChapters }

            for (index, incoming) in work.chapters.enumerated() {
                let number = Double(incoming.number)
                let mappedID = incoming.sourceID.flatMap { oldMapping[$0] }.flatMap(UUID.init(uuidString:))
                let matched = oldChapters.first { $0.id == mappedID } ?? (oldMapping.isEmpty ? oldChapters.first { $0.chapterNumber == number } : nil)
                let chapter = matched ?? LocalFanficChapter(id: UUID(), fanficId: fanficID, chapterNumber: number)
                if let oldPath = matched?.localTextPath { replacedPaths.append(oldPath) }
                if let sourceID = incoming.sourceID { newMapping[sourceID] = chapter.id.uuidString }
                usedIDs.insert(chapter.id)
                chapter.chapterNumber = number
                if chapter.modelContext == nil { modelContext.insert(chapter) }
                chapter.fanfic = fanfic
                chapter.title = incoming.title
                chapter.wordCount = incoming.content.split(whereSeparator: \.isWhitespace).count
                chapter.localTextPath = paths[index]
                chapter.scrapeStatus = "scraped"
                chapter.isDownloaded = true
                chapter.downloadStatus = .complete
                chapter.downloadedAt = .now
                chapter.downloadError = nil
            }
            // Chapters removed by the author remain readable locally. Their ordinal
            // is moved after the current source chapters to avoid duplicate ordering.
            for (offset, chapter) in (partial ? [] : oldChapters.filter({ !usedIDs.contains($0.id) })).enumerated() {
                chapter.scrapeStatus = "removed-at-source"
                chapter.chapterNumber = Double(work.chapters.count + offset + 1)
            }
            for (bookmark, chapterID) in bookmarkChapters {
                if let chapter = oldChapters.first(where: { $0.id == chapterID }) { bookmark.chapterNumber = chapter.chapterNumber }
            }
            if let chapter = oldChapters.first(where: { $0.id == lastChapterID }) { fanfic.lastReadChapterNumber = chapter.chapterNumber }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            await AO3ImportStorage.shared.remove(paths)
            throw error
        }
        UserDefaults.standard.set(newMapping, forKey: mappingKey)
        await AO3ImportStorage.shared.remove(replacedPaths)
        if sourceKey == "ffnet" && !partial { try? FileManager.default.removeItem(at: Self.ffnetCheckpoint(canonicalURL)) }
        AstralLogger.info("Imported story locally | chapters=\(work.chapters.count)\(partial ? " (partial)" : "")", context: "AO3Import")
        await FanficThumbnailService.repair(fanfic, context: modelContext, sourceCover: work.thumbnailURL)
        return fanfic
    }

    private func readFFNet(script: String, browser: WKWebView, canonical: URL, context: ModelContext) async throws -> AO3ImportResponse {
        // Chapters load in a hidden page that shares the browser's cookies, so the
        // visible page stays where the reader left it while the import runs.
        let background = FFNetBackgroundPage()
        defer { background.close() }
        ContentBlocker.shared.apply(to: background.webView)
        func navigate(_ url: URL) async throws {
            let view = background.webView
            defer { if Task.isCancelled { view.stopLoading() } }
            view.load(URLRequest(url: url))
            let started = Date()
            var challengedAt: Date?
            try await Task.sleep(for: .milliseconds(300))
            while true {
                try Task.checkCancellation()
                let requested = url.path.split(separator: "/")
                let state = (try? await view.callAsyncJavaScript(Self.ffnetPageState, arguments: ["storyID": String(requested[1]), "chapterNumber": Int(requested[2]) ?? 1], in: nil, contentWorld: .defaultClient)) as? String
                if state == "ready" { return }
                if state == "challenge", challengedAt == nil { challengedAt = Date() }
                // An automatic check usually clears within seconds; one that needs a
                // person stops the import so it can be completed in the browser.
                if let challengedAt, Date().timeIntervalSince(challengedAt) > 25 { view.stopLoading(); throw FFNetLoadError.verification(url) }
                if challengedAt == nil, Date().timeIntervalSince(started) > 45 { view.stopLoading(); throw AO3ImportError.message(for: "timeout") }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        func extract(_ view: WKWebView, title: String = "", count: Int = 0) async throws -> AO3ImportResponse {
            let value = try await view.callAsyncJavaScript(script, arguments: ["workURL": canonical.absoluteString, "singleChapter": true, "fallbackTitle": title, "expectedCount": count], in: nil, contentWorld: .defaultClient)
            try Task.checkCancellation()
            guard let json = value as? String, let data = json.data(using: .utf8) else { throw AO3ImportError("FFNet returned unreadable chapter data.") }
            return try JSONDecoder().decode(AO3ImportResponse.self, from: data)
        }
        let parts = canonical.path.split(separator: "/")
        guard parts.count >= 2 else { throw AO3ImportError("Open an FFNet story first.") }
        let root = URL(string: browser.url?.scheme == "https" ? "https://" + (browser.url?.host ?? "www.fanfiction.net") : "https://www.fanfiction.net")!
        func chapterURL(_ number: Int) -> URL { root.appendingPathComponent("s/\(parts[1])/\(number)/") }
        var first: AO3ImportResponse
        if browser.url?.path.split(separator: "/").dropFirst(2).first == "1" { first = try await extract(browser) }
        else {
            do { try await navigate(chapterURL(1)) }
            catch FFNetLoadError.verification(let page) { browser.load(URLRequest(url: page)); throw AO3ImportError.message(for: "verification") }
            first = try await extract(background.webView)
        }
        if first.error != nil { return first }
        guard var work = first.work, let firstCount = first.expectedChapters, (0...2000).contains(firstCount), work.chapters.count == 1, firstCount > 0 || first.nextChapter == 2 else { throw AO3ImportError("FFNet's chapter list is incomplete.") }
        var count = firstCount
        let checkpointURL = Self.ffnetCheckpoint(canonical)
        // A checkpoint resumes a stopped import, including one saved to the library
        // as a partial story, for up to two weeks.
        if let data = try? Data(contentsOf: checkpointURL), data.count <= 55 * 1024 * 1024,
           let saved = try? JSONDecoder().decode(FFNetCheckpoint.self, from: data),
           saved.expected == count, saved.work.title == work.title,
           (try? checkpointURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map({ Date().timeIntervalSince($0) < 14 * 86_400 }) == true,
           saved.work.chapters.first?.content.split(whereSeparator: \.isWhitespace).map(String.init) == work.chapters.first?.content.split(whereSeparator: \.isWhitespace).map(String.init),
           !saved.work.chapters.isEmpty, saved.work.chapters.count <= count,
           saved.work.chapters.enumerated().allSatisfy({ $0.element.number == $0.offset + 1 }) {
            work = saved.work
            work.thumbnailURL = first.work?.thumbnailURL ?? work.thumbnailURL
        }
        func checkpoint() throws {
            try FileManager.default.createDirectory(at: checkpointURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(FFNetCheckpoint(expected: count, work: work)).write(to: checkpointURL, options: .atomic)
        }
        var bytes = work.chapters.reduce(0) { $0 + $1.content.utf8.count }
        let job = try context.fetch(FetchDescriptor<LocalScrapeJob>()).first { $0.status == "running" && $0.sourceUrl == canonical.absoluteString && $0.sourceKey == "ffnet" }
        job?.totalChapters = count; job?.chaptersScraped = work.chapters.count; try context.save()
        var hasMore = count > work.chapters.count || (count == 0 && first.nextChapter != nil)
        do {
            while hasMore {
                let number = work.chapters.count + 1
                guard number <= 2000 else { throw AO3ImportError.message(for: "tooLarge") }
                // Paced like reading rather than a burst, which is what trips
                // FanFiction.net's check on long stories.
                try await Task.sleep(for: .seconds(Double.random(in: 2.5...4.5) + (number % 25 == 0 ? 10 : 0)))
                try await navigate(chapterURL(number))
                let result = try await extract(background.webView, title: work.title, count: count)
                if let error = result.error { throw AO3ImportError.message(for: error) }
                guard let reported = result.expectedChapters, let chapter = result.work?.chapters.first,
                      chapter.number == number, reported == 0 || count == 0 || reported == count else {
                    throw AO3ImportError("FFNet's chapters changed during import. Retry to save a consistent copy.")
                }
                if reported > 0 { count = reported }
                bytes += chapter.content.utf8.count
                guard bytes <= 50 * 1024 * 1024 else { throw AO3ImportError.message(for: "tooLarge") }
                work.chapters.append(chapter)
                hasMore = count > number || (count == 0 && result.nextChapter != nil)
                if !hasMore && count == 0 { count = number }
                if number % 5 == 0 { try checkpoint() }
                job?.totalChapters = count; job?.chaptersScraped = number
                job?.currentStep = count > 0 ? "Fetching chapter \(number) of \(count)" : "Fetching chapter \(number)"
                try context.save()
            }
        } catch is CancellationError {
            try? checkpoint(); throw CancellationError()
        } catch {
            try? checkpoint()
            var page: URL?
            if case .verification(let url)? = error as? FFNetLoadError { page = url }
            throw FFNetStopped(work: work, expected: count > work.chapters.count ? count : work.chapters.count + 1,
                               reason: page == nil ? error : AO3ImportError.message(for: "verification"), verificationPage: page)
        }
        guard count == work.chapters.count else { throw AO3ImportError.message(for: "incomplete") }
        try checkpoint()
        return AO3ImportResponse(error: nil, work: work, expectedChapters: count)
    }

    /// "ready" once the requested chapter's text is on the page, "challenge" while
    /// FanFiction.net shows its verification page, otherwise "loading".
    private static let ffnetPageState = """
    if (document.querySelector('#challenge-form, #cf-challenge-running, .cf-turnstile') || /just a moment|verify you are human|attention required/i.test(document.title)) return 'challenge';
    const parts = location.pathname.split('/');
    if (document.readyState !== 'loading' && parts[2] === storyID && Number(parts[3] || 1) === chapterNumber && document.querySelector('#storytext,#storycontent,.storycontent,#story_content')) return 'ready';
    return 'loading';
    """

    private enum FFNetLoadError: Error { case verification(URL) }

    /// An FFNet import that stopped after fetching at least its first chapter.
    private struct FFNetStopped: Error {
        let work: AO3WorkImport
        let expected: Int
        let reason: Error
        let verificationPage: URL?
    }

    private struct FFNetCheckpoint: Codable { let expected: Int; let work: AO3WorkImport }
    private static func ffnetCheckpoint(_ canonical: URL) -> URL {
        URL.cachesDirectory.appendingPathComponent("ffnet-import/" + (canonical.path.split(separator: "/").dropFirst().first.map(String.init) ?? "unknown") + ".json")
    }
    private static func date(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}

private struct AO3ImportResponse: Decodable {
    let error: String?
    let work: AO3WorkImport?
    var expectedChapters: Int? = nil
    var nextChapter: Int? = nil
}

private struct AO3WorkImport: Codable, Sendable {
    let title: String
    let authors: [String]
    let summary: String
    let fandom: String
    let rating: String
    let characters: String
    let pairing: String
    let warnings: String
    let freeformTags: String
    let wordCount: Int?
    let complete: Bool
    let publishedAt: String
    let updatedAt: String
    let hits: Int?
    let kudos: Int?
    let commentsCount: Int?
    let bookmarksCount: Int?
    var thumbnailURL: String? = nil
    var chapters: [AO3ChapterImport]
}

private struct AO3ChapterImport: Codable, Sendable {
    let sourceID: String?
    let number: Int
    let title: String
    let content: String
}

private actor AO3ImportStorage {
    static let shared = AO3ImportStorage()

    func write(_ chapters: [AO3ChapterImport], fanficID: UUID, importID: UUID) throws -> [String] {
        let documents = URL.documentsDirectory
        let directory = "fanfics/\(fanficID)/\(importID)"
        let destination = documents.appendingPathComponent(directory, isDirectory: true)
        let values = try documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let required = Int64(chapters.reduce(0) { $0 + $1.content.utf8.count }) + 50 * 1024 * 1024
        if let available = values.volumeAvailableCapacityForImportantUsage, available < required {
            throw AO3ImportError("There isn't enough free space to save this work.")
        }
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            return try chapters.map { chapter in
                try Task.checkCancellation()
                let path = "\(directory)/ch\(chapter.number).txt"
                try chapter.content.write(to: documents.appendingPathComponent(path), atomically: true, encoding: .utf8)
                return path
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func remove(_ paths: [String]) {
        for path in paths {
            let url = URL.documentsDirectory.appendingPathComponent(path).standardizedFileURL
            guard url.path.hasPrefix(URL.documentsDirectory.appendingPathComponent("fanfics").path + "/") else { continue }
            try? FileManager.default.removeItem(at: url)
            let directory = url.deletingLastPathComponent()
            if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
}

private struct AO3ImportError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) { errorDescription = message }

    static func message(for code: String) -> Self {
        switch code {
        case "verification": Self("Complete the source's verification in the browser, then tap Import again.")
        case "login": Self("Sign in to the source in the browser to access this work, then tap Import again.")
        case "rateLimited": Self("The source is limiting requests. Please wait before importing again.")
        case "notFound": Self("This story was removed or is no longer available.")
        case "incomplete": Self("The source didn't provide every chapter. Check the full work in the browser, then tap Import again. Your saved copy hasn't changed.")
        case "timeout": Self("The source took too long to respond. Please try again.")
        case "tooLarge": Self("This work exceeds the on-device import limit of 2,000 chapters or 50 MB of text.")
        case "network": Self("Couldn't connect to the source. Check your connection and try again.")
        case "unavailable": Self("The source is temporarily unavailable. Please try again later.")
        case "wrongPage": Self("Open the FFNet story itself in Add, then tap Import.")
        case "chapterList": Self("FFNet did not expose a complete chapter list or a Next link. Open the story with its chapter navigation visible, then retry. Your saved copy has not changed.")
        case "invalidWork": Self("The story title or details could not be read. Open the story's own page in the browser, then tap Import again.")
        default: Self("Open an accessible story in the browser, then tap Import.")
        }
    }
}

/// An FFNet import that saved part of a story before stopping. The partial story
/// is in the library; Continue import on the story page fetches the rest.
struct FFNetPartialImport: LocalizedError {
    let storyID: UUID
    let saved: Int
    let expected: Int
    let reason: Error
    let needsVerification: Bool

    var errorDescription: String? {
        let progress = "Saved \(saved) of \(expected) chapters to your library."
        if needsVerification {
            return progress + " FanFiction.net asked to confirm you're human. Complete the check on this page, then tap Continue import."
        }
        return progress + " " + reason.localizedDescription + " Tap Continue import on the story page to fetch the rest."
    }
}

/// A hidden page that shares the browser's website data, including any check
/// already passed. It stays attached to the window, out of sight, because WebKit
/// throttles pages that are not in one.
@MainActor
private final class FFNetBackgroundPage {
    let webView: WKWebView

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: CGRect(x: -2000, y: 0, width: 390, height: 844), configuration: config)
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        window?.insertSubview(webView, at: 0)
    }

    func close() {
        webView.stopLoading()
        webView.removeFromSuperview()
    }
}
