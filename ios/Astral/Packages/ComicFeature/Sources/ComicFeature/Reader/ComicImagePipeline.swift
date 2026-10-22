import Foundation
import CoreGraphics
import ImageIO
import Networking

/// Reader-only memory cache. Permanent page storage still belongs to
/// ChapterDownloadService and the user's offline comic/byte limits.
actor ComicImagePipeline {
    struct Request: Hashable, Sendable {
        let url: URL
        let referrer: String?
        let pixelWidth: Int
    }

    /// Source order works for webtoon, LTR and RTL without changing gestures.
    static func prefetchIndices(page: Int, count: Int) -> [Int] {
        [page, page + 1, page + 2, page - 1].filter { $0 >= 0 && $0 < count }
    }

    private struct Cached {
        let image: CGImage
        let cost: Int
        var access: UInt64
    }
    private struct Flight {
        let id: UUID
        let task: Task<CGImage, Error>
        var clients: Set<UUID>
    }
    private struct Slot {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private let byteLimit: Int
    private let countLimit: Int
    private let concurrency: Int
    private let load: @Sendable (Request) async throws -> CGImage
    private var cache: [Request: Cached] = [:]
    private var cacheBytes = 0
    private var clock: UInt64 = 0
    private var flights: [Request: Flight] = [:]
    private var slots: [Slot] = []
    private var running = 0

    init(byteLimit: Int = 64 * 1024 * 1024, countLimit: Int = 6, concurrency: Int = 2,
         load: @escaping @Sendable (Request) async throws -> CGImage = ComicImagePreparation.load) {
        self.byteLimit = max(0, byteLimit)
        self.countLimit = max(1, countLimit)
        self.concurrency = max(1, concurrency)
        self.load = load
    }

    func image(for request: Request, prefetch: Bool = false) async throws -> CGImage {
        try Task.checkCancellation()
        clock &+= 1
        if var entry = cache[request] {
            entry.access = clock; cache[request] = entry
            return entry.image
        }
        let client = UUID()
        let flight: Flight
        if var existing = flights[request] {
            existing.clients.insert(client); flights[request] = existing
            flight = existing
            // A visible page takes precedence over queued speculative work.
            if !prefetch, let index = slots.firstIndex(where: { $0.id == existing.id }) {
                slots.insert(slots.remove(at: index), at: 0)
            }
        } else {
            let id = UUID()
            let task = Task(priority: prefetch ? .utility : .userInitiated) {
                try await self.perform(request, id: id, prefetch: prefetch)
            }
            flight = Flight(id: id, task: task, clients: [client])
            flights[request] = flight
        }
        defer { release(request, flight: flight.id, client: client) }
        return try await withTaskCancellationHandler {
            let image = try await flight.task.value
            try Task.checkCancellation()
            return image
        } onCancel: {
            Task { await self.release(request, flight: flight.id, client: client) }
        }
    }

    func clear() {
        let tasks = flights.values.map(\.task)
        flights.removeAll()
        tasks.forEach { $0.cancel() }
        let waiting = slots; slots.removeAll()
        waiting.forEach { $0.continuation.resume(throwing: CancellationError()) }
        cache.removeAll(); cacheBytes = 0
    }

    private func release(_ request: Request, flight: UUID, client: UUID) {
        guard var entry = flights[request], entry.id == flight,
              entry.clients.remove(client) != nil else { return }
        if entry.clients.isEmpty {
            flights[request] = nil; entry.task.cancel()
            if let index = slots.firstIndex(where: { $0.id == flight }) {
                slots.remove(at: index).continuation.resume(throwing: CancellationError())
            }
        } else { flights[request] = entry }
    }

    private func perform(_ request: Request, id: UUID, prefetch: Bool) async throws -> CGImage {
        try Task.checkCancellation()
        if running < concurrency { running += 1 }
        else {
            try await withCheckedThrowingContinuation { continuation in
                let slot = Slot(id: id, continuation: continuation)
                if prefetch { slots.append(slot) } else { slots.insert(slot, at: 0) }
            }
        }
        defer {
            if slots.isEmpty { running -= 1 }
            else { slots.removeFirst().continuation.resume() }
        }
        try Task.checkCancellation()
        let image = try await load(request)
        try Task.checkCancellation()
        if flights[request]?.id == id { store(image, for: request) }
        return image
    }

    private func store(_ image: CGImage, for request: Request) {
        let cost = image.bytesPerRow * image.height
        guard cost <= byteLimit else { return }
        if let old = cache.removeValue(forKey: request) { cacheBytes -= old.cost }
        while !cache.isEmpty && (cache.count >= countLimit || cacheBytes + cost > byteLimit) {
            guard let oldest = cache.min(by: { $0.value.access < $1.value.access })?.key,
                  let removed = cache.removeValue(forKey: oldest) else { break }
            cacheBytes -= removed.cost
        }
        clock &+= 1
        cache[request] = Cached(image: image, cost: cost, access: clock)
        cacheBytes += cost
    }
}

enum ComicImagePreparation {
    /// The concurrent boundary includes file I/O, resizing and eager decoding.
    /// Originals on disk are unchanged; only the display image is downsampled.
    @concurrent static func load(_ request: ComicImagePipeline.Request) async throws -> CGImage {
        try Task.checkCancellation()
        let file: URL
        let temporary: Bool
        if request.url.isFileURL {
            file = request.url; temporary = false
        } else {
            guard ["https", "http"].contains(request.url.scheme?.lowercased() ?? "") else { throw URLError(.badURL) }
            let (url, response) = try await SourceImageTransport.session.download(for:
                SourceImageTransport.request(request.url, referrer: request.referrer))
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                try? FileManager.default.removeItem(at: url)
                throw URLError(.badServerResponse)
            }
            file = url; temporary = true
        }
        defer { if temporary { try? FileManager.default.removeItem(at: file) } }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        // Keep some zoom headroom, but cap very tall strips at 12 megapixels.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let displayWidth = (5...8).contains(orientation) ? height : width
        let scale = min(1, Double(max(256, min(2560, request.pixelWidth))) / displayWidth,
                        sqrt(12_000_000 / (width * height)))
        // Account for the shorter edge rounding up, especially on long strips.
        let proposedEdge = max(1, Int((max(width, height) * scale).rounded(.down)))
        let shortEdge = max(1, ceil(Double(proposedEdge) * min(width, height) / max(width, height)))
        let edge = max(1, min(proposedEdge, Int(12_000_000 / shortEdge)))
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        try Task.checkCancellation()
        return image
    }
}
