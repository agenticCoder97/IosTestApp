import Foundation
import CryptoKit

/// Purgeable disk cache for comic pages streamed while reading. Without it,
/// scrolling back up a long chapter downloads every strip again. It lives in
/// Library/Caches (the OS may clear it), is capped, and is separate from saved
/// chapters, which still count against the offline comic limits.
public actor ComicPageCache {
    public static let shared = ComicPageCache()

    public static let byteLimit: Int64 = 400 * 1024 * 1024
    private static let trimTarget: Int64 = 300 * 1024 * 1024

    private let fileManager = FileManager.default
    private let directory: URL
    private var knownBytes: Int64?

    private init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("comicPages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// MangaDex at-home servers change host between requests while the
    /// `/data/<hash>/<file>` path stays the same, so those are keyed by path.
    /// Only MangaDex's own image hosts qualify; every other page keeps its
    /// scheme and host so two sources can never share an entry.
    public nonisolated static func key(for url: URL) -> String {
        if url.isFileURL { return "file:" + url.path }
        let host = url.host?.lowercased() ?? ""
        let path = url.path
        let mangaDexHost = url.scheme == "https" && (host == "uploads.mangadex.org" || host.hasSuffix(".mangadex.network"))
        if mangaDexHost, path.hasPrefix("/data/") || path.hasPrefix("/data-saver/") { return "mangadex:" + path }
        return (url.scheme ?? "") + "://" + host + path + (url.query.map { "?" + $0 } ?? "")
    }

    public func file(for url: URL) -> URL? {
        let file = location(for: url)
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return file
    }

    /// Moves a validated download into the cache and returns its new location.
    public func store(_ downloaded: URL, for url: URL) throws -> URL {
        let file = location(for: url)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: file.path) { try? fileManager.removeItem(at: file) }
        let total = knownBytes ?? measure()
        try fileManager.moveItem(at: downloaded, to: file)
        let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        knownBytes = total + size
        if let bytes = knownBytes, bytes > Self.byteLimit { trim() }
        return file
    }

    public func totalBytes() -> Int64 {
        let bytes = measure()
        knownBytes = bytes
        return bytes
    }

    public func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        knownBytes = 0
    }

    private func location(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(Self.key(for: url).utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".page")
    }

    private func entries() -> [(url: URL, size: Int64, date: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files.compactMap { file in
            guard let values = try? file.resourceValues(forKeys: Set(keys)), let size = values.fileSize else { return nil }
            return (file, Int64(size), values.contentModificationDate ?? .distantPast)
        }
    }

    private func measure() -> Int64 { entries().reduce(0) { $0 + $1.size } }

    /// Least recently read pages go first.
    private func trim() {
        let files = entries().sorted { $0.date < $1.date }
        var total = files.reduce(0) { $0 + $1.size }
        for file in files where total > Self.trimTarget {
            try? fileManager.removeItem(at: file.url)
            total -= file.size
        }
        knownBytes = total
    }
}
