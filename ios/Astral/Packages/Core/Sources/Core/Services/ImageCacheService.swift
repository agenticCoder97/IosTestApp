import Foundation

/// LRU disk cache for thumbnail and cover images.
/// Stores images in Library/Caches/thumbnails/ with a 200MB limit.
public actor ImageCacheService {
    public static let shared = ImageCacheService()

    private let fileManager = FileManager.default
    private let maxBytes: Int64 = 200 * 1024 * 1024  // 200MB
    private let evictToBytes: Int64 = 150 * 1024 * 1024  // Evict to 150MB

    private var cacheDir: URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("thumbnails")
    }

    private init() {
        // Ensure cache directory exists
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("thumbnails")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Check if an image is cached. Returns file URL if available.
    public func cachedURL(for remotePath: String) -> URL? {
        let fileURL = cacheDir.appendingPathComponent(cacheKey(for: remotePath))
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        // Touch modification date for LRU tracking
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
        return fileURL
    }

    /// Cache image data and return the local URL.
    public func cache(data: Data, for remotePath: String) throws -> URL {
        let fileURL = cacheDir.appendingPathComponent(cacheKey(for: remotePath))
        try data.write(to: fileURL)
        Task { await evictIfNeeded() }
        return fileURL
    }

    /// Evict oldest files until under the limit.
    private func evictIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, size: Int64, date: Date)] = []

        for file in files {
            guard let attrs = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = attrs.fileSize,
                  let date = attrs.contentModificationDate else { continue }
            totalSize += Int64(size)
            fileInfos.append((file, Int64(size), date))
        }

        guard totalSize > maxBytes else { return }

        // Sort oldest first for LRU eviction
        fileInfos.sort { $0.date < $1.date }

        for info in fileInfos {
            guard totalSize > evictToBytes else { break }
            try? fileManager.removeItem(at: info.url)
            totalSize -= info.size
        }
    }

    private func cacheKey(for remotePath: String) -> String {
        // Simple hash-based filename using djb2
        let hash = remotePath.utf8.reduce(into: UInt64(5381)) { hash, byte in
            hash = hash &* 33 &+ UInt64(byte)
        }
        let ext = (remotePath as NSString).pathExtension
        return "\(hash).\(ext.isEmpty ? "jpg" : ext)"
    }
}
