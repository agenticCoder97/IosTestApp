import Foundation
import WebKit
import Networking

/// Sources whose APIs only answer the site's own scripts. Their pages open in the
/// hidden loader, and the importer reads the responses the site received there
/// (see `SourceResponseTap`).
@MainActor
enum TappedComicSources {
    static let sources: Set<String> = ["mangafire"]

    static func work(url: URL, source: String, loader: DeviceSourcePageLoader) async throws -> DeviceComicService.Work {
        guard source == "mangafire" else { throw DeviceComicService.SourceError.message("This source can't be imported.") }
        return try await MangaFire.work(url: url, loader: loader)
    }

    static func pages(chapterURL: URL, source: String, loader: DeviceSourcePageLoader) async throws -> [String] {
        guard source == "mangafire", let id = MangaFire.chapterID(chapterURL) else {
            throw DeviceComicService.SourceError.message("This chapter link isn't a MangaFire chapter.")
        }
        try await loader.load(chapterURL)
        let capture = try await SourceResponseTap.wait(in: loader.webView, path: "^/api/chapters/\(id)$")
        return try MangaFire.pages(Data(capture.body.utf8))
    }

    // MARK: - MangaFire

    enum MangaFire {
        /// `/title/vq0w6-psychopath-in-murim` → `vq0w6`.
        static func titleID(_ url: URL) -> String? {
            let parts = url.path.split(separator: "/")
            guard parts.count >= 2, parts[0] == "title", let id = parts[1].split(separator: "-").first, !id.isEmpty else { return nil }
            return String(id)
        }

        static func chapterID(_ url: URL) -> String? {
            let parts = url.path.split(separator: "/")
            guard parts.count == 4, parts[0] == "title", parts[2] == "chapter", parts[3].allSatisfy(\.isNumber) else { return nil }
            return String(parts[3])
        }

        /// The site lists chapters 20 at a time; step through its own pager.
        @MainActor static func work(url: URL, loader: DeviceSourcePageLoader) async throws -> DeviceComicService.Work {
            guard let id = titleID(url) else { throw DeviceComicService.SourceError.message("Open a MangaFire title page in Add.") }
            try await loader.load(url)
            let view = loader.webView
            let title = try await SourceResponseTap.wait(in: view, path: "^/api/titles/\(id)$")
            let listPath = "^/api/titles/\(id)/chapters$"
            var lists: [Data] = []
            var page = 1
            while true {
                let capture = try await SourceResponseTap.wait(in: view, path: listPath, timeout: .seconds(20)) { $0.queryValue("page") == String(page) }
                let data = Data(capture.body.utf8)
                lists.append(data)
                guard let meta = try JSONDecoder().decode(ChapterList.self, from: data).meta, meta.page < meta.lastPage, page < 500 else { break }
                page += 1
                let clicked = try await view.callAsyncJavaScript(nextPageScript, arguments: ["next": page], in: nil, contentWorld: .defaultClient) as? Bool
                guard clicked == true else { throw DeviceComicService.SourceError.message("MangaFire's chapter list stopped at page \(page - 1). Retry the import.") }
            }
            return try work(title: Data(title.body.utf8), chapterLists: lists, seriesURL: url)
        }

        static let nextPageScript = """
            const nav = document.querySelector('nav.npager'); if (!nav) return false;
            const buttons = [...nav.querySelectorAll('button')];
            const target = buttons.find(b => b.textContent.trim() === String(next))
                || buttons.find(b => /next|›|»|→/i.test((b.getAttribute('aria-label') || '') + b.textContent));
            if (!target) return false; target.click(); return true;
            """

        static func work(title: Data, chapterLists: [Data], seriesURL: URL) throws -> DeviceComicService.Work {
            let info = try JSONDecoder().decode(TitleResponse.self, from: title).data
            let parts = seriesURL.path.split(separator: "/")
            guard parts.count >= 2, let host = seriesURL.host else { throw DeviceComicService.SourceError.message("Open a MangaFire title page in Add.") }
            var seen = Set<Double>(), chapters: [DeviceComicService.Chapter] = []
            for list in chapterLists {
                for item in try JSONDecoder().decode(ChapterList.self, from: list).items where seen.insert(item.number).inserted {
                    let number = item.number.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(item.number)) : String(item.number)
                    let name = item.name?.trimmingCharacters(in: .whitespaces) ?? ""
                    chapters.append(.init(url: "https://\(host)/title/\(parts[1])/chapter/\(item.id)",
                                          number: item.number, title: name.isEmpty ? "Chapter \(number)" : "Chapter \(number): \(name)", pages: []))
                }
            }
            chapters.sort { $0.number < $1.number }
            let tags = (info.genres ?? []).map { ["name": $0.title, "tag_type": "genre"] } + (info.themes ?? []).map { ["name": $0.title, "tag_type": "theme"] }
            let people = ((info.authors ?? []) + (info.artists ?? [])).map(\.title)
            return .init(title: info.title, description: plainText(info.synopsisHtml ?? ""), authors: people.reduce(into: []) { if !$0.contains($1) { $0.append($1) } },
                         tags: tags, cover: [info.poster?.large, info.poster?.medium].compactMap { $0 }.first { $0.hasPrefix("https://") }, chapters: chapters)
        }

        static func pages(_ data: Data) throws -> [String] {
            try JSONDecoder().decode(ChapterResponse.self, from: data).data.pages.map(\.url)
        }

        static func plainText(_ html: String) -> String {
            let text = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&#039;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
            return text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        struct Named: Decodable { let title: String }
        struct TitleResponse: Decodable {
            let data: Info
            struct Info: Decodable {
                let title: String; let synopsisHtml: String?
                let poster: Poster?; let genres: [Named]?; let themes: [Named]?; let authors: [Named]?; let artists: [Named]?
            }
            struct Poster: Decodable { let medium: String?; let large: String? }
        }
        struct ChapterList: Decodable {
            let items: [Item]; let meta: Meta?
            struct Item: Decodable { let id: Int; let number: Double; let name: String? }
            struct Meta: Decodable { let page: Int; let lastPage: Int }
        }
        struct ChapterResponse: Decodable {
            let data: Chapter
            struct Chapter: Decodable { let pages: [Page] }
            struct Page: Decodable { let url: String }
        }
    }
}
