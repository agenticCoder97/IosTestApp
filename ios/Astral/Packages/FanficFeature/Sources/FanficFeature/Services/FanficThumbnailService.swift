import Foundation
import ImageIO
import UniformTypeIdentifiers
import SwiftData
import Core

/// Restores the former source-work artwork lookup on the phone. Only fandom tags
/// are used for Wikipedia lookup; story text, titles and browser cookies are not sent.
actor FanficThumbnailService {
    static let shared = FanficThumbnailService()
    struct Request: Sendable, Equatable {
        let id: UUID
        let fandom: String?
        let sourceURL: String?
        let sourceCover: String?
        let currentPath: String?
    }
    struct Artwork: Sendable { let path: String; let credit: String? }
    private var active: [UUID: Task<Artwork?, Never>] = [:]
    private var misses: [UUID: (request: Request, date: Date)] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = ["User-Agent": "Astral/1.0 (https://github.com/agenticCoder97/IosTestApp)"]
        return URLSession(configuration: configuration)
    }()

    @MainActor static func repair(_ story: LocalFanfic, context: ModelContext, sourceCover: String? = nil) async {
        guard ["ao3", "ffnet"].contains(story.sourceKey) else { return }
        let oldPath = story.thumbnailPath
        let request = Request(id: story.id, fandom: story.fandom, sourceURL: story.sourceUrl, sourceCover: sourceCover, currentPath: oldPath)
        guard let art = await shared.resolve(request), !Task.isCancelled,
              !story.isDeleted, story.modelContext != nil, story.thumbnailPath == oldPath else { return }
        story.thumbnailPath = art.path
        do {
            try context.save()
            if let credit = art.credit { UserDefaults.standard.set(credit, forKey: "reading.fanficCoverSource." + story.id.uuidString) }
        } catch { story.thumbnailPath = oldPath }
    }

    func resolve(_ request: Request) async -> Artwork? {
        if let path = request.currentPath, let url = URL(string: path), url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) { return nil }
        if let path = request.currentPath, path.hasPrefix("documents:fanficCovers/"),
           FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent(String(path.dropFirst(10))).path) { return nil }
        if let task = active[request.id] { return await task.value }
        if request.sourceCover == nil, let miss = misses[request.id], miss.request == request,
           Date().timeIntervalSince(miss.date) < 300 { return nil }
        let task = Task { await acquire(request) }
        active[request.id] = task
        let result = await task.value
        active[request.id] = nil
        if result == nil { misses[request.id] = (request, .now) }
        return result
    }

    private func acquire(_ request: Request) async -> Artwork? {
        let candidates = [request.sourceCover, request.currentPath].compactMap { $0 }.compactMap(URL.init(string:)).filter { $0.scheme == "https" }
        for url in candidates {
            if let path = await download(url, id: request.id, referrer: request.sourceURL) {
                return Artwork(path: path, credit: request.sourceURL)
            }
        }
        guard let title = Self.sourceTitle(request.fandom) else { return nil }
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = ["action":"query", "format":"json", "formatversion":"2", "redirects":"1", "prop":"pageimages", "piprop":"thumbnail", "pilicense":"any", "pithumbsize":"600", "titles":title].map { URLQueryItem(name: $0.key, value: $0.value) }
        do {
            let (data, response) = try await session.data(from: components.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { return nil }
            let result = try JSONDecoder().decode(WikiResult.self, from: data)
            guard let source = result.query.pages.first(where: { $0.missing != true })?.thumbnail?.source,
                  let url = URL(string: source), url.scheme == "https", ["upload.wikimedia.org", "thumb.wikimedia.org"].contains(url.host ?? ""),
                  let path = await download(url, id: request.id, referrer: nil) else { return nil }
            var credit = URLComponents(string: "https://en.wikipedia.org/w/index.php")!
            credit.queryItems = [URLQueryItem(name: "title", value: title)]
            return Artwork(path: path, credit: credit.url?.absoluteString)
        } catch { return nil }
    }

    private func download(_ url: URL, id: UUID, referrer: String?) async -> String? {
        do {
            var request = URLRequest(url: url)
            if let referrer { request.setValue(referrer, forHTTPHeaderField: "Referer") }
            let (temporary, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 8 * 1024 * 1024,
                  let image = CGImageSourceCreateWithURL(temporary as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, [kCGImageSourceCreateThumbnailFromImageAlways:true, kCGImageSourceThumbnailMaxPixelSize:600, kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
            let file = URL.documentsDirectory.appendingPathComponent("fanficCovers/" + id.uuidString + ".jpg")
            let buffer = NSMutableData()
            guard let target = CGImageDestinationCreateWithData(buffer, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(target, thumbnail, [kCGImageDestinationLossyCompressionQuality:0.85] as CFDictionary)
            guard CGImageDestinationFinalize(target), !Task.isCancelled else { return nil }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (buffer as Data).write(to: file, options: .atomic)
            return "documents:fanficCovers/" + file.lastPathComponent
        } catch { return nil }
    }

    static func sourceTitle(_ fandom: String?) -> String? {
        guard let fandom else { return nil }
        let aliases = ["harry potter - j. k. rowling":"Harry Potter", "harry potter":"Harry Potter", "naruto":"Naruto", "star wars - all media types":"Star Wars", "star wars prequel trilogy":"Star Wars", "star wars: the clone wars (2008)":"Star Wars", "marvel cinematic universe":"Marvel Cinematic Universe", "the avengers (marvel movies)":"Marvel Cinematic Universe", "marvel (comics)":"Marvel Comics", "batman - all media types":"Batman", "sherlock (tv)":"Sherlock (TV series)", "supernatural (tv 2005)":"Supernatural (American TV series)", "teen wolf (tv)":"Teen Wolf (2011 TV series)", "boku no hero academia":"My Hero Academia", "haikyuu!!":"Haikyu!!", "bungou stray dogs":"Bungo Stray Dogs", "highschool dxd":"High School DxD"]
        var candidates = Set<String>()
        for part in fandom.components(separatedBy: ",") {
            var tag = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, tag.range(of: #"(?i)\b(rpf|real person fiction|original work|no fandom|multi-fandom|multifandom|crossover)\b"#, options: .regularExpression) == nil else { return nil }
            tag = aliases[tag.lowercased()] ?? tag
            tag = tag.components(separatedBy: "|").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? tag
            tag = tag.replacingOccurrences(of: #"(?i)\s+-\s+all media types\s*$"#, with: "", options: .regularExpression)
            tag = tag.components(separatedBy: " - ").first ?? tag
            tag = tag.replacingOccurrences(of: #"(?i)\s*\([^)]*(anime|manga|movies?|tv|television|comics?|cartoons?|video games?|books?|novels?|web series|podcasts?)[^)]*\)\s*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            candidates.insert(aliases[tag.lowercased()] ?? tag)
        }
        return candidates.count == 1 ? candidates.first : nil
    }
    private struct WikiResult: Decodable { let query: Query
        struct Query: Decodable { let pages: [Page] }
        struct Page: Decodable { let missing: Bool?; let thumbnail: Thumbnail? }
        struct Thumbnail: Decodable { let source: String }
    }
}
