# Offline Download Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make downloaded content reliably readable offline — fix the broken fanfic reader, add atomic downloads, orphan cleanup, background session for comics, thumbnail caching, and clear offline UI indicators.

**Architecture:** Hybrid approach — hardened per-feature download services with atomic writes + background URLSession for bulk comic downloads. New `DownloadState` enum in Core drives all state transitions. `OrphanCleanupService` reconciles disk vs SwiftData on every launch.

**Tech Stack:** Swift 5.9+, SwiftData, URLSession background configuration, FileManager atomic operations, iOS 17.2+

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Core/Sources/Core/Models/DownloadState.swift` | State enum + helpers |
| `Core/Sources/Core/Services/OrphanCleanupService.swift` | Reconcile disk/SwiftData on launch |
| `Core/Sources/Core/Services/ImageCacheService.swift` | LRU thumbnail disk cache |
| `FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift` | Extracted fanfic download logic |
| `Networking/Sources/Networking/BackgroundDownloadSession.swift` | Background URLSession wrapper |
| `DesignSystem/Sources/DesignSystem/Components/CachedAsyncImage.swift` | Thumbnail view with cache |

### Modified Files
| File | Changes |
|------|---------|
| `Core/Sources/Core/Models/LocalComicChapter.swift` | Add `downloadState`, `downloadedAt`, `downloadSizeBytes`, `downloadError` |
| `Core/Sources/Core/Models/LocalFanficChapter.swift` | Add `downloadState`, `downloadedAt`, `downloadError` |
| `Core/Sources/Core/Models/LocalComic.swift` | Add `lastSyncedAt`, computed `isFullyDownloaded` |
| `Core/Sources/Core/Models/LocalFanfic.swift` | Add `lastSyncedAt`, computed `isFullyDownloaded` |
| `ComicFeature/.../Services/ChapterDownloadService.swift` | Atomic writes, temp dir, validation, guards |
| `FanficFeature/.../Reader/FanficReaderView.swift` | Local-first loading in `loadChapter()` |
| `ComicFeature/.../Reader/ComicReaderView.swift` | Page count validation, offline error state |
| `FanficFeature/.../Library/FanficDetailView.swift` | Replace inline download with service call |
| `AstralApp.swift` | Add orphan cleanup on launch, background session handler |

---

## Task 1: DownloadState Enum & Model Migrations

**Files:**
- Create: `ios/Astral/Packages/Core/Sources/Core/Models/DownloadState.swift`
- Modify: `ios/Astral/Packages/Core/Sources/Core/Models/LocalComicChapter.swift`
- Modify: `ios/Astral/Packages/Core/Sources/Core/Models/LocalFanficChapter.swift`
- Modify: `ios/Astral/Packages/Core/Sources/Core/Models/LocalComic.swift`
- Modify: `ios/Astral/Packages/Core/Sources/Core/Models/LocalFanfic.swift`

- [ ] **Step 1: Create DownloadState enum**

Create `ios/Astral/Packages/Core/Sources/Core/Models/DownloadState.swift`:

```swift
import Foundation

public enum DownloadState: String, Codable {
    case none
    case queued
    case downloading
    case failed
    case complete
}
```

- [ ] **Step 2: Add fields to LocalComicChapter**

In `ios/Astral/Packages/Core/Sources/Core/Models/LocalComicChapter.swift`, add after line 14 (`localPagesPath`):

```swift
public var downloadState: String = "none"
public var downloadedAt: Date?
public var downloadSizeBytes: Int64?
public var downloadError: String?
```

Note: SwiftData stores enums as their raw values. We use `String` with the `DownloadState` raw values for SwiftData compatibility on iOS 17.2. Add a computed helper:

```swift
public var downloadStatus: DownloadState {
    get { DownloadState(rawValue: downloadState) ?? .none }
    set { downloadState = newValue.rawValue }
}
```

Update the `isDownloaded` property to be computed (remove stored, add computed):

```swift
public var isDownloaded: Bool {
    get { downloadStatus == .complete }
    set { downloadStatus = newValue ? .complete : .none }
}
```

Wait — SwiftData `@Model` properties must be stored. We cannot make `isDownloaded` computed without breaking the schema. Instead, keep `isDownloaded` as a stored property for backward compat but always update it alongside `downloadState`. We'll maintain both during transition.

- [ ] **Step 3: Add fields to LocalFanficChapter**

In `ios/Astral/Packages/Core/Sources/Core/Models/LocalFanficChapter.swift`, add after line 16 (`scrapeStatus`):

```swift
public var downloadState: String = "none"
public var downloadedAt: Date?
public var downloadError: String?
```

Add the same computed helper:

```swift
public var downloadStatus: DownloadState {
    get { DownloadState(rawValue: downloadState) ?? .none }
    set { downloadState = newValue.rawValue }
}
```

- [ ] **Step 4: Add lastSyncedAt to LocalComic and LocalFanfic**

In `ios/Astral/Packages/Core/Sources/Core/Models/LocalComic.swift`, add after `archivedAt`:

```swift
public var lastSyncedAt: Date?
```

Add computed property after existing computed properties:

```swift
public var isFullyDownloaded: Bool {
    guard let chs = chapters, !chs.isEmpty else { return false }
    return chs.allSatisfy { $0.downloadStatus == .complete }
}
```

In `ios/Astral/Packages/Core/Sources/Core/Models/LocalFanfic.swift`, add after `completedAt`:

```swift
public var lastSyncedAt: Date?
```

Add computed property:

```swift
public var isFullyDownloaded: Bool {
    guard let chs = chapters, !chs.isEmpty else { return false }
    return chs.allSatisfy { $0.downloadStatus == .complete }
}
```

- [ ] **Step 5: Build and verify**

Run: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED. SwiftData handles new optional/defaulted properties as lightweight migrations automatically.

- [ ] **Step 6: Commit**

```bash
git add ios/Astral/Packages/Core/Sources/Core/Models/DownloadState.swift \
        ios/Astral/Packages/Core/Sources/Core/Models/LocalComicChapter.swift \
        ios/Astral/Packages/Core/Sources/Core/Models/LocalFanficChapter.swift \
        ios/Astral/Packages/Core/Sources/Core/Models/LocalComic.swift \
        ios/Astral/Packages/Core/Sources/Core/Models/LocalFanfic.swift
git commit -m "[ios] add DownloadState enum and model fields for download resilience"
```

---

## Task 2: FanficDownloadService (Extract from DetailView)

**Files:**
- Create: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift`

- [ ] **Step 1: Create Services directory and FanficDownloadService**

Create directory: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/`

Create `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift`:

```swift
import Foundation
import SwiftData
import Core
import Networking

/// Downloads fanfic chapter text to device Documents directory for offline reading.
@MainActor
final class FanficDownloadService {
    static let shared = FanficDownloadService()
    private init() {}

    private let fileManager = FileManager.default
    private var activeDownloads: Set<UUID> = []

    private var documentsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var tempDownloadDir: URL {
        fileManager.temporaryDirectory.appendingPathComponent("astral-downloads")
    }

    /// Download a single chapter's text content to device.
    func downloadChapter(
        fanfic: LocalFanfic,
        chapter: LocalFanficChapter,
        modelContext: ModelContext
    ) async {
        guard !activeDownloads.contains(chapter.id) else { return }
        activeDownloads.insert(chapter.id)
        defer { activeDownloads.remove(chapter.id) }

        chapter.downloadStatus = .downloading
        chapter.downloadError = nil

        do {
            // Check disk space (text is small but be safe)
            try checkDiskSpace(estimatedBytes: 1_000_000) // 1MB buffer for text

            let response: FanficChapterResponse = try await APIClient.shared.request(
                .fanficChapter(fanficId: fanfic.id, chapterId: chapter.id)
            )

            guard let content = response.content, !content.isEmpty else {
                chapter.downloadStatus = .failed
                chapter.downloadError = "Empty chapter content from server"
                try? modelContext.save()
                return
            }

            // Write to temp first
            let tempFile = tempDownloadDir.appendingPathComponent("\(fanfic.id)_ch\(chapterFileName(chapter)).txt")
            try fileManager.createDirectory(at: tempFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: tempFile, atomically: true, encoding: .utf8)

            // Atomic move to final location
            let relPath = "fanfics/\(fanfic.id)/ch\(chapterFileName(chapter)).txt"
            let finalURL = documentsDir.appendingPathComponent(relPath)
            try fileManager.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            // Remove existing file if present (re-download case)
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: tempFile, to: finalURL)

            // Update model
            chapter.localTextPath = relPath
            chapter.downloadStatus = .complete
            chapter.downloadedAt = .now
            chapter.isDownloaded = true
            try modelContext.save()

        } catch {
            chapter.downloadStatus = .failed
            chapter.downloadError = error.localizedDescription
            try? modelContext.save()
            AstralLogger.error("Download ch \(chapter.chapterNumber) failed: \(error)", context: "FanficDownload")
        }
    }

    /// Download all pending chapters for a fanfic.
    func downloadAllChapters(
        fanfic: LocalFanfic,
        chapters: [LocalFanficChapter],
        modelContext: ModelContext,
        onProgress: @escaping (Int, Int) -> Void
    ) async {
        let pending = chapters.filter { $0.downloadStatus != .complete && $0.scrapeStatus == "scraped" }
        guard !pending.isEmpty else { return }

        for chapter in pending {
            chapter.downloadStatus = .queued
        }
        try? modelContext.save()

        for (idx, chapter) in pending.enumerated() {
            await downloadChapter(fanfic: fanfic, chapter: chapter, modelContext: modelContext)
            onProgress(idx + 1, pending.count)
        }

        fanfic.isDownloaded = chapters.allSatisfy { $0.downloadStatus == .complete }
        try? modelContext.save()
    }

    /// Delete all downloaded chapter files for a fanfic.
    func deleteAllChapters(
        fanfic: LocalFanfic,
        chapters: [LocalFanficChapter],
        modelContext: ModelContext
    ) {
        let fanficDir = documentsDir.appendingPathComponent("fanfics/\(fanfic.id)")
        try? fileManager.removeItem(at: fanficDir)
        for chapter in chapters {
            chapter.localTextPath = nil
            chapter.downloadStatus = .none
            chapter.isDownloaded = false
            chapter.downloadedAt = nil
            chapter.downloadError = nil
        }
        fanfic.isDownloaded = false
        try? modelContext.save()
    }

    // MARK: - Helpers

    /// Format chapter number for filename: "3.0" → "3", "3.5" → "3.5"
    private func chapterFileName(_ chapter: LocalFanficChapter) -> String {
        chapter.chapterNumber.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(chapter.chapterNumber))"
            : String(format: "%.1f", chapter.chapterNumber)
    }

    private func checkDiskSpace(estimatedBytes: Int64) throws {
        let attrs = try fileManager.attributesOfFileSystem(forPath: documentsDir.path)
        let freeSpace = (attrs[.systemFreeSize] as? Int64) ?? 0
        let buffer: Int64 = 50 * 1024 * 1024 // 50MB minimum buffer
        guard freeSpace > estimatedBytes + buffer else {
            throw DownloadError.insufficientDiskSpace
        }
    }
}

enum DownloadError: LocalizedError {
    case insufficientDiskSpace
    case fileValidationFailed(String)

    var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace: return "Not enough storage space"
        case .fileValidationFailed(let reason): return "File validation failed: \(reason)"
        }
    }
}
```

- [ ] **Step 2: Replace inline download logic in FanficDetailView**

In `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift`, replace the `handleDownloadTap()` method (lines 471-516) with:

```swift
private func handleDownloadTap() {
    guard !isDownloading else { return }
    let allComplete = chapters.allSatisfy { $0.downloadStatus == .complete }

    if allComplete {
        // Delete mode
        FanficDownloadService.shared.deleteAllChapters(
            fanfic: fanfic,
            chapters: chapters,
            modelContext: modelContext
        )
        return
    }

    isDownloading = true
    Task {
        await FanficDownloadService.shared.downloadAllChapters(
            fanfic: fanfic,
            chapters: chapters,
            modelContext: modelContext,
            onProgress: { done, total in
                downloadProgress = (done, total)
            }
        )
        isDownloading = false
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift \
        ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift
git commit -m "[ios] extract FanficDownloadService with atomic writes and disk space checks"
```

---

## Task 3: Harden ChapterDownloadService (Comics)

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift`

- [ ] **Step 1: Rewrite ChapterDownloadService with atomic downloads**

Replace the entire file `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift`:

```swift
import Foundation
import SwiftData
import Core
import Networking

/// Downloads comic chapter pages to device Documents directory for offline reading.
@MainActor
final class ChapterDownloadService {
    static let shared = ChapterDownloadService()
    private init() {}

    private let fileManager = FileManager.default
    private var activeDownloads: Set<UUID> = []

    private var documentsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var tempDownloadDir: URL {
        fileManager.temporaryDirectory.appendingPathComponent("astral-downloads")
    }

    // MARK: - Download

    /// Download all pages for a single chapter with atomic completion.
    func downloadChapter(
        comicId: UUID,
        chapter: LocalComicChapter,
        modelContext: ModelContext
    ) async throws {
        guard !activeDownloads.contains(chapter.id) else { return }
        activeDownloads.insert(chapter.id)
        defer { activeDownloads.remove(chapter.id) }

        chapter.downloadStatus = .downloading
        chapter.downloadError = nil

        do {
            // Estimate: ~500KB per page
            let estimatedBytes = Int64(chapter.totalPages) * 500_000
            try checkDiskSpace(estimatedBytes: estimatedBytes)

            let pages: [PageResponse] = try await APIClient.shared.request(
                .chapterPages(comicId: comicId, chapterId: chapter.id)
            )

            // Write to temp directory
            let tempDir = tempDownloadDir.appendingPathComponent(chapter.id.uuidString)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            var totalBytes: Int64 = 0

            try await withThrowingTaskGroup(of: Int64.self) { group in
                for page in pages {
                    group.addTask {
                        guard let url = URL(string: AppConfig.staticBaseURL + page.filePath) else {
                            throw DownloadError.fileValidationFailed("Invalid URL for page \(page.pageNumber)")
                        }
                        let (data, _) = try await URLSession.shared.data(from: url)

                        // Validate image data (JPEG or PNG magic bytes)
                        try self.validateImageData(data, pageNumber: page.pageNumber)

                        let fileName = String(format: "page_%04d.jpg", page.pageNumber)
                        let fileURL = tempDir.appendingPathComponent(fileName)
                        try data.write(to: fileURL)
                        return Int64(data.count)
                    }
                }
                for try await bytes in group {
                    totalBytes += bytes
                }
            }

            // Atomic move: temp → final
            let relativeDir = "comics/\(comicId)/\(chapter.id)"
            let finalDir = documentsDir.appendingPathComponent(relativeDir)

            // Remove existing if re-downloading
            if fileManager.fileExists(atPath: finalDir.path) {
                try fileManager.removeItem(at: finalDir)
            }
            try fileManager.createDirectory(at: finalDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: tempDir, to: finalDir)

            // Update model
            chapter.localPagesPath = relativeDir
            chapter.downloadStatus = .complete
            chapter.downloadedAt = .now
            chapter.downloadSizeBytes = totalBytes
            chapter.isDownloaded = true

            do {
                try modelContext.save()
            } catch {
                // Save failed — remove moved files to stay consistent
                try? fileManager.removeItem(at: finalDir)
                chapter.localPagesPath = nil
                chapter.downloadStatus = .failed
                chapter.downloadError = "Database save failed"
                chapter.isDownloaded = false
                throw error
            }

        } catch {
            // Cleanup temp on failure
            let tempDir = tempDownloadDir.appendingPathComponent(chapter.id.uuidString)
            try? fileManager.removeItem(at: tempDir)

            chapter.downloadStatus = .failed
            chapter.downloadError = error.localizedDescription
            chapter.isDownloaded = false
            try? modelContext.save()
            throw error
        }
    }

    /// Download ALL chapters for a comic sequentially.
    func downloadAllChapters(
        comic: LocalComic,
        chapters: [LocalComicChapter],
        modelContext: ModelContext,
        onProgress: @escaping (Int, Int) -> Void
    ) async {
        let pending = chapters.filter { $0.downloadStatus != .complete && $0.scrapeStatus == "scraped" }
        guard !pending.isEmpty else { return }

        for chapter in pending {
            chapter.downloadStatus = .queued
        }
        try? modelContext.save()

        for (idx, chapter) in pending.enumerated() {
            do {
                try await downloadChapter(comicId: comic.id, chapter: chapter, modelContext: modelContext)
            } catch {
                AstralLogger.error("Download failed ch \(chapter.chapterNumber): \(error)", context: "Download")
            }
            onProgress(idx + 1, pending.count)
        }

        comic.isDownloaded = chapters.allSatisfy { $0.downloadStatus == .complete }
        try? modelContext.save()
    }

    // MARK: - Local Files

    /// Load locally saved page URLs for a chapter. Returns nil if not available.
    func localPageURLs(for chapter: LocalComicChapter) -> [URL]? {
        guard let relativePath = chapter.localPagesPath else { return nil }
        let chapterDir = documentsDir.appendingPathComponent(relativePath)
        guard let files = try? fileManager.contentsOfDirectory(at: chapterDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        let sorted = files
            .filter { $0.pathExtension == "jpg" || $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return sorted.isEmpty ? nil : sorted
    }

    // MARK: - Deletion

    /// Delete locally saved pages for a single chapter.
    func deleteChapter(comicId: UUID, chapter: LocalComicChapter, modelContext: ModelContext) {
        guard let relativePath = chapter.localPagesPath else { return }
        let chapterDir = documentsDir.appendingPathComponent(relativePath)
        try? fileManager.removeItem(at: chapterDir)
        chapter.localPagesPath = nil
        chapter.downloadStatus = .none
        chapter.isDownloaded = false
        chapter.downloadedAt = nil
        chapter.downloadSizeBytes = nil
        chapter.downloadError = nil
        try? modelContext.save()
    }

    /// Delete all locally saved pages for a comic.
    func deleteAllChapters(comic: LocalComic, chapters: [LocalComicChapter], modelContext: ModelContext) {
        let comicDir = documentsDir.appendingPathComponent("comics/\(comic.id)")
        try? fileManager.removeItem(at: comicDir)
        for chapter in chapters {
            chapter.localPagesPath = nil
            chapter.downloadStatus = .none
            chapter.isDownloaded = false
            chapter.downloadedAt = nil
            chapter.downloadSizeBytes = nil
            chapter.downloadError = nil
        }
        comic.isDownloaded = false
        try? modelContext.save()
    }

    // MARK: - Validation

    /// Validate downloaded image data has correct magic bytes.
    private nonisolated func validateImageData(_ data: Data, pageNumber: Int) throws {
        guard data.count > 1024 else {
            throw DownloadError.fileValidationFailed("Page \(pageNumber): file too small (\(data.count) bytes)")
        }
        let jpegMagic: [UInt8] = [0xFF, 0xD8, 0xFF]
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

        let header = Array(data.prefix(4))
        let isJPEG = header.starts(with: jpegMagic)
        let isPNG = header.starts(with: pngMagic)

        guard isJPEG || isPNG else {
            throw DownloadError.fileValidationFailed("Page \(pageNumber): not a valid JPEG/PNG")
        }
    }

    private func checkDiskSpace(estimatedBytes: Int64) throws {
        let attrs = try fileManager.attributesOfFileSystem(forPath: documentsDir.path)
        let freeSpace = (attrs[.systemFreeSize] as? Int64) ?? 0
        let buffer: Int64 = 50 * 1024 * 1024
        guard freeSpace > estimatedBytes + buffer else {
            throw DownloadError.insufficientDiskSpace
        }
    }
}
```

- [ ] **Step 2: Move DownloadError to Core (shared between features)**

Move `DownloadError` from `FanficDownloadService.swift` into `DownloadState.swift` in Core so both services can use it:

In `ios/Astral/Packages/Core/Sources/Core/Models/DownloadState.swift`, append:

```swift
public enum DownloadError: LocalizedError {
    case insufficientDiskSpace
    case fileValidationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace: return "Not enough storage space"
        case .fileValidationFailed(let reason): return "File validation failed: \(reason)"
        }
    }
}
```

Remove the `DownloadError` enum from `FanficDownloadService.swift`.

- [ ] **Step 3: Build and verify**

Run: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift \
        ios/Astral/Packages/Core/Sources/Core/Models/DownloadState.swift \
        ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Services/FanficDownloadService.swift
git commit -m "[ios] harden ChapterDownloadService with atomic writes, validation, and disk checks"
```

---

## Task 4: Fix Fanfic Reader — Local-First Loading

**Files:**
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift`

- [ ] **Step 1: Add offline error state property**

Near the other `@State` properties at the top of `FanficReaderView`, add:

```swift
@State private var offlineError = false
```

- [ ] **Step 2: Replace loadChapter() with local-first implementation**

Replace the `loadChapter()` method (lines 485-508) with:

```swift
private func loadChapter() async {
    AstralLogger.info("loadChapter: ch \(currentChapter.chapterNumber) (id=\(currentChapter.id)) for '\(fanfic.title)'", context: "FanficReader")
    offlineError = false

    if let previewContent {
        chapterContent = previewContent
        calculateScrollTarget()
        isLoading = false
        return
    }

    // 1. Try local file first (offline reading)
    if let localPath = currentChapter.localTextPath {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(localPath)
        if let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
            chapterContent = content
            AstralLogger.info("loadChapter: loaded \(content.count) chars from local file", context: "FanficReader")
            calculateScrollTarget()
            isLoading = false
            return
        } else {
            // File missing or corrupt — reset download state
            currentChapter.downloadStatus = .none
            currentChapter.localTextPath = nil
            currentChapter.isDownloaded = false
            try? modelContext.save()
            AstralLogger.warning("loadChapter: local file missing/corrupt, falling through to network", context: "FanficReader")
        }
    }

    // 2. Try network
    do {
        let response: FanficChapterResponse = try await APIClient.shared.request(
            .fanficChapter(fanficId: fanfic.id, chapterId: currentChapter.id)
        )
        guard !Task.isCancelled else { return }
        chapterContent = response.content ?? ""
        AstralLogger.info("loadChapter: got \(chapterContent.count) chars from network", context: "FanficReader")
    } catch {
        guard !Task.isCancelled else { return }
        // 3. Both local and network failed
        chapterContent = ""
        offlineError = true
        AstralLogger.error("loadChapter failed: \(error)", context: "FanficReader")
    }

    calculateScrollTarget()
    isLoading = false
}
```

- [ ] **Step 3: Add offline error UI**

In the `body` of `FanficReaderView`, find where `isLoading` shows a ProgressView and add an offline state nearby. After the loading check, add:

```swift
if offlineError {
    VStack(spacing: 16) {
        Image(systemName: "cloud.slash")
            .font(.system(size: 44))
            .foregroundStyle(AstralColors.muted)
        Text("Chapter not available offline")
            .font(AstralTypography.body)
            .foregroundStyle(AstralColors.body)
        Text("Download this chapter or connect to read")
            .font(AstralTypography.caption)
            .foregroundStyle(AstralColors.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- [ ] **Step 4: Build and verify**

Run: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift
git commit -m "[ios] fix fanfic reader — load local files first for offline reading"
```

---

## Task 5: Harden Comic Reader — Validate Local Files

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift`

- [ ] **Step 1: Add offline error state**

Near other `@State` properties in `ComicReaderView`, add:

```swift
@State private var offlineError = false
```

- [ ] **Step 2: Update loadPages() local file check**

Replace lines 899-906 (the local files section of `loadPages()`) with:

```swift
// Try local files first (device-saved chapter)
if let urls = ChapterDownloadService.shared.localPageURLs(for: chapter) {
    if urls.count == chapter.totalPages || chapter.totalPages == 0 {
        localPageURLs = urls
        pages = []
        AstralLogger.info("loadPages: using \(urls.count) local pages", context: "ComicReader")
        isLoading = false
        return
    } else {
        // Page count mismatch — partial/corrupt download
        chapter.downloadStatus = .failed
        chapter.downloadError = "Expected \(chapter.totalPages) pages, found \(urls.count)"
        AstralLogger.warning("loadPages: local page count mismatch (\(urls.count)/\(chapter.totalPages)), falling through to network", context: "ComicReader")
    }
}
```

- [ ] **Step 3: Add offline error handling to the network fallback**

Replace lines 908-918 (the network fetch section) with:

```swift
localPageURLs = nil
offlineError = false
do {
    let response: [PageResponse] = try await APIClient.shared.request(
        .chapterPages(comicId: comic.id, chapterId: chapter.id)
    )
    pages = applyPageSkip(response)
    AstralLogger.info("loadPages: got \(pages.count) pages", context: "ComicReader")
} catch {
    AstralLogger.error("loadPages failed: \(error)", context: "ComicReader")
    offlineError = true
}
isLoading = false
```

- [ ] **Step 4: Add offline error overlay in body**

In the `ZStack` of the `body`, add after the loading spinner section:

```swift
if offlineError && pages.isEmpty && localPageURLs == nil {
    VStack(spacing: 16) {
        Image(systemName: "cloud.slash")
            .font(.system(size: 44))
            .foregroundStyle(AstralColors.muted)
        Text("Pages not available offline")
            .font(AstralTypography.body)
            .foregroundStyle(AstralColors.white)
        Text("Download this chapter or connect to read")
            .font(AstralTypography.caption)
            .foregroundStyle(AstralColors.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- [ ] **Step 5: Build and verify**

Run: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Reader/ComicReaderView.swift
git commit -m "[ios] harden comic reader — validate local page count, add offline error state"
```

---

## Task 6: OrphanCleanupService

**Files:**
- Create: `ios/Astral/Packages/Core/Sources/Core/Services/OrphanCleanupService.swift`
- Modify: `ios/Astral/AstralApp.swift`

- [ ] **Step 1: Create OrphanCleanupService**

Create directory: `ios/Astral/Packages/Core/Sources/Core/Services/`

Create `ios/Astral/Packages/Core/Sources/Core/Services/OrphanCleanupService.swift`:

```swift
import Foundation
import SwiftData

/// Reconciles on-disk downloaded files with SwiftData state on app launch.
/// Removes orphaned files and resets stale download states.
public final class OrphanCleanupService {

    private static let fileManager = FileManager.default

    private static var documentsDir: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var tempDownloadDir: URL {
        fileManager.temporaryDirectory.appendingPathComponent("astral-downloads")
    }

    /// Run all cleanup tasks. Call once on app launch.
    @MainActor
    public static func cleanOnLaunch(modelContext: ModelContext) {
        cleanTempDirectory()
        reconcileComicDownloads(modelContext: modelContext)
        reconcileFanficDownloads(modelContext: modelContext)
        migrateFanficChapterPaths(modelContext: modelContext)
        AstralLogger.info("OrphanCleanupService: cleanup complete", context: "Cleanup")
    }

    // MARK: - Temp Cleanup

    /// Remove any leftover temp download files from interrupted downloads.
    private static func cleanTempDirectory() {
        if fileManager.fileExists(atPath: tempDownloadDir.path) {
            try? fileManager.removeItem(at: tempDownloadDir)
            AstralLogger.info("Cleaned temp download directory", context: "Cleanup")
        }
    }

    // MARK: - Comic Reconciliation

    @MainActor
    private static func reconcileComicDownloads(modelContext: ModelContext) {
        // 1. Check SwiftData records marked complete — verify files exist
        let descriptor = FetchDescriptor<LocalComicChapter>()
        guard let chapters = try? modelContext.fetch(descriptor) else { return }

        for chapter in chapters where chapter.downloadStatus == .complete {
            guard let path = chapter.localPagesPath else {
                // Marked complete but no path — reset
                chapter.downloadStatus = .none
                chapter.isDownloaded = false
                continue
            }
            let dir = documentsDir.appendingPathComponent(path)
            if !fileManager.fileExists(atPath: dir.path) {
                // Files missing — reset state
                chapter.localPagesPath = nil
                chapter.downloadStatus = .none
                chapter.isDownloaded = false
                chapter.downloadedAt = nil
                chapter.downloadSizeBytes = nil
                AstralLogger.warning("Reset orphaned comic chapter \(chapter.id): files missing", context: "Cleanup")
            }
        }

        // 2. Reset any stuck "downloading" or "queued" states (app was killed mid-download)
        for chapter in chapters where chapter.downloadStatus == .downloading || chapter.downloadStatus == .queued {
            chapter.downloadStatus = .none
            chapter.downloadError = "Interrupted — app was closed during download"
        }

        try? modelContext.save()
    }

    // MARK: - Fanfic Reconciliation

    @MainActor
    private static func reconcileFanficDownloads(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<LocalFanficChapter>()
        guard let chapters = try? modelContext.fetch(descriptor) else { return }

        for chapter in chapters where chapter.downloadStatus == .complete {
            guard let path = chapter.localTextPath else {
                chapter.downloadStatus = .none
                chapter.isDownloaded = false
                continue
            }
            let file = documentsDir.appendingPathComponent(path)
            if !fileManager.fileExists(atPath: file.path) {
                chapter.localTextPath = nil
                chapter.downloadStatus = .none
                chapter.isDownloaded = false
                chapter.downloadedAt = nil
                AstralLogger.warning("Reset orphaned fanfic chapter \(chapter.id): file missing", context: "Cleanup")
            }
        }

        // Reset stuck states
        for chapter in chapters where chapter.downloadStatus == .downloading || chapter.downloadStatus == .queued {
            chapter.downloadStatus = .none
            chapter.downloadError = "Interrupted — app was closed during download"
        }

        try? modelContext.save()
    }

    // MARK: - Migration: Fanfic Int→Double Filenames

    @MainActor
    private static func migrateFanficChapterPaths(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<LocalFanficChapter>()
        guard let chapters = try? modelContext.fetch(descriptor) else { return }

        for chapter in chapters {
            guard let path = chapter.localTextPath else { continue }
            // Check if path uses Int format for a non-integer chapter number
            let hasDecimal = chapter.chapterNumber.truncatingRemainder(dividingBy: 1) != 0
            guard hasDecimal else { continue }

            let intName = "ch\(Int(chapter.chapterNumber)).txt"
            let correctName = "ch\(String(format: "%.1f", chapter.chapterNumber)).txt"

            if path.hasSuffix(intName) {
                let oldURL = documentsDir.appendingPathComponent(path)
                let newPath = path.replacingOccurrences(of: intName, with: correctName)
                let newURL = documentsDir.appendingPathComponent(newPath)

                if fileManager.fileExists(atPath: oldURL.path) {
                    try? fileManager.moveItem(at: oldURL, to: newURL)
                    chapter.localTextPath = newPath
                    AstralLogger.info("Migrated fanfic chapter path: \(intName) → \(correctName)", context: "Cleanup")
                }
            }
        }
        try? modelContext.save()
    }
}
```

- [ ] **Step 2: Wire OrphanCleanupService into AstralApp**

In `ios/Astral/AstralApp.swift`, modify the body to run cleanup on launch. Replace lines 49-55:

```swift
var body: some Scene {
    WindowGroup {
        RootView()
            .task { ContentBlocker.shared.precompile() }
            .task {
                let context = sharedModelContainer.mainContext
                OrphanCleanupService.cleanOnLaunch(modelContext: context)
            }
    }
    .modelContainer(sharedModelContainer)
}
```

- [ ] **Step 3: Build and verify**

Run: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/Packages/Core/Sources/Core/Services/OrphanCleanupService.swift \
        ios/Astral/AstralApp.swift
git commit -m "[ios] add OrphanCleanupService — reconcile disk/SwiftData on launch"
```

---

## Task 7: ImageCacheService & CachedAsyncImage

**Files:**
- Create: `ios/Astral/Packages/Core/Sources/Core/Services/ImageCacheService.swift`
- Create: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/CachedAsyncImage.swift`
- Modify: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StoryThumbnail.swift`

- [ ] **Step 1: Create ImageCacheService**

Create `ios/Astral/Packages/Core/Sources/Core/Services/ImageCacheService.swift`:

```swift
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
        try? FileManager.default.createDirectory(
            at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("thumbnails"),
            withIntermediateDirectories: true
        )
    }

    /// Check if an image is cached. Returns file URL if available.
    public func cachedURL(for remotePath: String) -> URL? {
        let fileURL = cacheDir.appendingPathComponent(cacheKey(for: remotePath))
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        // Touch access date for LRU tracking
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

        // Sort oldest first
        fileInfos.sort { $0.date < $1.date }

        for info in fileInfos {
            guard totalSize > evictToBytes else { break }
            try? fileManager.removeItem(at: info.url)
            totalSize -= info.size
        }
    }

    private func cacheKey(for remotePath: String) -> String {
        // Simple hash-based filename
        let hash = remotePath.utf8.reduce(into: UInt64(5381)) { hash, byte in
            hash = hash &* 33 &+ UInt64(byte)
        }
        let ext = (remotePath as NSString).pathExtension
        return "\(hash).\(ext.isEmpty ? "jpg" : ext)"
    }
}
```

- [ ] **Step 2: Create CachedAsyncImage view**

Create `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/CachedAsyncImage.swift`:

```swift
import SwiftUI
import Core

/// AsyncImage that checks ImageCacheService before fetching from network.
/// Falls back to a placeholder when both cache and network are unavailable.
public struct CachedAsyncImage: View {
    let remotePath: String?
    let baseURL: String
    let width: CGFloat
    let height: CGFloat

    @State private var image: UIImage?
    @State private var isLoading = true

    public init(remotePath: String?, baseURL: String, width: CGFloat, height: CGFloat) {
        self.remotePath = remotePath
        self.baseURL = baseURL
        self.width = width
        self.height = height
    }

    public var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(AstralColors.surface)
                    .overlay {
                        ProgressView()
                            .tint(AstralColors.muted)
                    }
            } else {
                Rectangle()
                    .fill(AstralColors.surface)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(AstralColors.muted)
                    }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: remotePath) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let path = remotePath else {
            isLoading = false
            return
        }

        // 1. Check cache
        if let cachedURL = await ImageCacheService.shared.cachedURL(for: path),
           let uiImage = UIImage(contentsOfFile: cachedURL.path) {
            image = uiImage
            isLoading = false
            return
        }

        // 2. Fetch from network
        guard let url = URL(string: baseURL + path) else {
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let uiImage = UIImage(data: data) {
                _ = try? await ImageCacheService.shared.cache(data: data, for: path)
                image = uiImage
            }
        } catch {
            // Network failed, no cache — show placeholder
        }
        isLoading = false
    }
}
```

- [ ] **Step 3: Update StoryThumbnail to use CachedAsyncImage**

Read `StoryThumbnail.swift` first to understand current implementation, then replace its `AsyncImage` usage with `CachedAsyncImage`. The key change: wherever it uses `AsyncImage(url:)` for the thumbnail, swap to `CachedAsyncImage(remotePath:baseURL:width:height:)`.

- [ ] **Step 4: Build and verify**

Run: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ios/Astral/Packages/Core/Sources/Core/Services/ImageCacheService.swift \
        ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/CachedAsyncImage.swift \
        ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/StoryThumbnail.swift
git commit -m "[ios] add ImageCacheService and CachedAsyncImage for offline thumbnails"
```

---

## Task 8: BackgroundDownloadSession (Comics)

**Files:**
- Create: `ios/Astral/Packages/Networking/Sources/Networking/BackgroundDownloadSession.swift`
- Modify: `ios/Astral/AstralApp.swift`
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift`

- [ ] **Step 1: Create BackgroundDownloadSession**

Create `ios/Astral/Packages/Networking/Sources/Networking/BackgroundDownloadSession.swift`:

```swift
import Foundation
import Core

/// Background URLSession wrapper for bulk comic page downloads that survive app termination.
public final class BackgroundDownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let shared = BackgroundDownloadSession()

    private let sessionID = "com.astral.background-downloads"
    private let maxRetries = 3

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: sessionID)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Info about each in-flight download task
    private struct TaskInfo {
        let comicId: UUID
        let chapterId: UUID
        let pageNumber: Int
        let destinationDir: URL  // temp staging dir for this chapter
        var retryCount: Int = 0
    }

    private var taskMap: [Int: TaskInfo] = []  // taskIdentifier → info
    private let lock = NSLock()

    /// Completion handler provided by the system for background URL session events
    public var systemCompletionHandler: (() -> Void)?

    /// Published progress per chapter (observed by UI on main actor)
    @MainActor public var chapterProgress: [UUID: (completed: Int, total: Int)] = [:]

    /// Callback when all pages for a chapter finish (called on main actor)
    @MainActor public var onChapterComplete: ((UUID, UUID) -> Void)?  // (comicId, chapterId)
    @MainActor public var onChapterFailed: ((UUID, UUID, String) -> Void)?  // (comicId, chapterId, error)

    private override init() {
        super.init()
        // Touch session to reconnect on relaunch
        _ = session
    }

    // MARK: - Enqueue Downloads

    /// Enqueue all pages for a chapter as background download tasks.
    /// Pages are downloaded to a staging directory; caller handles atomic move on completion.
    @MainActor
    public func enqueueChapter(
        comicId: UUID,
        chapterId: UUID,
        pageURLs: [(pageNumber: Int, url: URL)],
        stagingDir: URL
    ) {
        chapterProgress[chapterId] = (completed: 0, total: pageURLs.count)

        for page in pageURLs {
            let task = session.downloadTask(with: page.url)
            let info = TaskInfo(
                comicId: comicId,
                chapterId: chapterId,
                pageNumber: page.pageNumber,
                destinationDir: stagingDir
            )
            lock.lock()
            taskMap[task.taskIdentifier] = info
            lock.unlock()
            task.resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        guard let info = taskMap[downloadTask.taskIdentifier] else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Move downloaded file to staging dir
        let fileName = String(format: "page_%04d.jpg", info.pageNumber)
        let destURL = info.destinationDir.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: info.destinationDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: location, to: destURL)
        } catch {
            AstralLogger.error("Background download: failed to move page \(info.pageNumber): \(error)", context: "BGDownload")
        }

        // Update progress
        Task { @MainActor in
            if var progress = chapterProgress[info.chapterId] {
                progress.completed += 1
                chapterProgress[info.chapterId] = progress

                // Check if chapter is complete
                if progress.completed >= progress.total {
                    onChapterComplete?(info.comicId, info.chapterId)
                    chapterProgress.removeValue(forKey: info.chapterId)
                }
            }
        }

        lock.lock()
        taskMap.removeValue(forKey: downloadTask.taskIdentifier)
        lock.unlock()
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error else { return }

        lock.lock()
        guard var info = taskMap[task.taskIdentifier] else {
            lock.unlock()
            return
        }
        taskMap.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        // Retry with resume data if available
        let nsError = error as NSError
        if info.retryCount < maxRetries,
           let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            info.retryCount += 1
            let newTask = session.downloadTask(withResumeData: resumeData)
            lock.lock()
            taskMap[newTask.taskIdentifier] = info
            lock.unlock()
            newTask.resume()
            AstralLogger.info("Background download: retrying page \(info.pageNumber) (attempt \(info.retryCount))", context: "BGDownload")
        } else {
            // Give up on this page → fail the chapter
            Task { @MainActor in
                let msg = "Page \(info.pageNumber) failed after \(info.retryCount + 1) attempts: \(error.localizedDescription)"
                onChapterFailed?(info.comicId, info.chapterId, msg)
                chapterProgress.removeValue(forKey: info.chapterId)
            }
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.systemCompletionHandler?()
            self?.systemCompletionHandler = nil
        }
    }
}
```

- [ ] **Step 2: Add background session handler to AstralApp**

In `ios/Astral/AstralApp.swift`, add an app delegate for background session handling. Before the `AstralApp` struct, add:

```swift
class AstralAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloadSession.shared.systemCompletionHandler = completionHandler
    }
}
```

Inside `AstralApp`, add:

```swift
@UIApplicationDelegateAdaptor(AstralAppDelegate.self) var appDelegate
```

Add `import Networking` to the imports.

- [ ] **Step 3: Add background download mode to ChapterDownloadService**

In `ChapterDownloadService.swift`, add a method for background bulk download:

```swift
/// Enqueue all pending chapters for background download (survives app kill).
func downloadAllChaptersBackground(
    comic: LocalComic,
    chapters: [LocalComicChapter],
    modelContext: ModelContext
) async {
    let pending = chapters.filter { $0.downloadStatus != .complete && $0.scrapeStatus == "scraped" }
    guard !pending.isEmpty else { return }

    // Set up completion handler
    BackgroundDownloadSession.shared.onChapterComplete = { [weak self] comicId, chapterId in
        guard let self else { return }
        self.finalizeBackgroundChapter(comicId: comicId, chapterId: chapterId, chapters: chapters, comic: comic, modelContext: modelContext)
    }
    BackgroundDownloadSession.shared.onChapterFailed = { comicId, chapterId, error in
        if let ch = chapters.first(where: { $0.id == chapterId }) {
            ch.downloadStatus = .failed
            ch.downloadError = error
            try? modelContext.save()
        }
    }

    for chapter in pending {
        do {
            try checkDiskSpace(estimatedBytes: Int64(chapter.totalPages) * 500_000)

            let pages: [PageResponse] = try await APIClient.shared.request(
                .chapterPages(comicId: comic.id, chapterId: chapter.id)
            )

            let stagingDir = tempDownloadDir.appendingPathComponent(chapter.id.uuidString)
            let pageURLs = pages.compactMap { page -> (pageNumber: Int, url: URL)? in
                guard let url = URL(string: AppConfig.staticBaseURL + page.filePath) else { return nil }
                return (page.pageNumber, url)
            }

            chapter.downloadStatus = .downloading
            try? modelContext.save()

            await BackgroundDownloadSession.shared.enqueueChapter(
                comicId: comic.id,
                chapterId: chapter.id,
                pageURLs: pageURLs,
                stagingDir: stagingDir
            )
        } catch {
            chapter.downloadStatus = .failed
            chapter.downloadError = error.localizedDescription
            try? modelContext.save()
        }
    }
}

/// Called when BackgroundDownloadSession finishes all pages for a chapter.
private func finalizeBackgroundChapter(
    comicId: UUID,
    chapterId: UUID,
    chapters: [LocalComicChapter],
    comic: LocalComic,
    modelContext: ModelContext
) {
    guard let chapter = chapters.first(where: { $0.id == chapterId }) else { return }

    let stagingDir = tempDownloadDir.appendingPathComponent(chapterId.uuidString)
    let relativeDir = "comics/\(comicId)/\(chapterId)"
    let finalDir = documentsDir.appendingPathComponent(relativeDir)

    do {
        if fileManager.fileExists(atPath: finalDir.path) {
            try fileManager.removeItem(at: finalDir)
        }
        try fileManager.createDirectory(at: finalDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: stagingDir, to: finalDir)

        chapter.localPagesPath = relativeDir
        chapter.downloadStatus = .complete
        chapter.downloadedAt = .now
        chapter.isDownloaded = true
        comic.isDownloaded = chapters.allSatisfy { $0.downloadStatus == .complete }
        try modelContext.save()
    } catch {
        chapter.downloadStatus = .failed
        chapter.downloadError = "Failed to finalize: \(error.localizedDescription)"
        try? modelContext.save()
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ios/Astral/Packages/Networking/Sources/Networking/BackgroundDownloadSession.swift \
        ios/Astral/AstralApp.swift \
        ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Services/ChapterDownloadService.swift
git commit -m "[ios] add BackgroundDownloadSession for bulk comic downloads surviving app kill"
```

---

## Task 9: Last Synced Timestamp & UI Integration

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ViewModels/ComicLibraryViewModel.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/ViewModels/FanficLibraryViewModel.swift`
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift`

- [ ] **Step 1: Update ViewModels to set lastSyncedAt on success**

In `ComicLibraryViewModel.swift`, after the successful fetch/sync block where comics are updated from the API response, add:

```swift
// After successful sync, update lastSyncedAt on all synced comics
for comic in comics {
    comic.lastSyncedAt = .now
}
```

Do the same in `FanficLibraryViewModel.swift`:

```swift
for fanfic in fanfics {
    fanfic.lastSyncedAt = .now
}
```

- [ ] **Step 2: Add "Last updated" display to library views**

In `ComicLibraryView.swift`, add a small subtitle below the library header or in the pull-to-refresh area. Find an appropriate place (e.g., below BackendStatusBanner) and add:

```swift
if let oldestSync = displayedComics.compactMap(\.lastSyncedAt).min() {
    HStack {
        Spacer()
        Text("Updated \(oldestSync, format: .relative(presentation: .named))")
            .font(AstralTypography.caption)
            .foregroundStyle(AstralColors.muted)
    }
    .padding(.horizontal, 16)
    .padding(.top, 4)
}
```

Add equivalent in `FanficLibraryView.swift`.

- [ ] **Step 3: Build and verify**

Run: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/ViewModels/ComicLibraryViewModel.swift \
        ios/Astral/Packages/FanficFeature/Sources/FanficFeature/ViewModels/FanficLibraryViewModel.swift \
        ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicLibraryView.swift \
        ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficLibraryView.swift
git commit -m "[ios] add last-synced timestamp display in library views"
```

---

## Task 10: Per-Chapter Download Status UI

**Files:**
- Modify: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift`
- Modify: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift`

- [ ] **Step 1: Add per-chapter status icons in ComicDetailView chapter list**

In the chapter list section of `ComicDetailView`, where each chapter row is rendered, add a trailing status icon:

```swift
// After existing chapter row content, add:
Spacer()
switch chapter.downloadStatus {
case .complete:
    Image(systemName: "arrow.down.circle.fill")
        .font(.system(size: 12))
        .foregroundStyle(AstralColors.success)
case .downloading, .queued:
    ProgressView()
        .scaleEffect(0.6)
case .failed:
    Image(systemName: "exclamationmark.circle.fill")
        .font(.system(size: 12))
        .foregroundStyle(AstralColors.error)
case .none:
    EmptyView()
}
```

- [ ] **Step 2: Add per-chapter status in FanficDetailView chapter list**

Same pattern in the fanfic chapter list rows.

- [ ] **Step 3: Update download button to show count**

In both detail views, update the download button label to show progress when partially downloaded:

```swift
let downloadedCount = chapters.filter { $0.downloadStatus == .complete }.count
// Show as badge: "8/12" next to download icon
```

- [ ] **Step 4: Build and verify**

Run: `cd ios/Astral && xcodebuild -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicDetailView.swift \
        ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficDetailView.swift
git commit -m "[ios] add per-chapter download status indicators in detail views"
```

---

## Task 11: XcodeGen & Final Build Verification

**Files:**
- Modify: `ios/Astral/project.yml` (if new files need explicit listing)

- [ ] **Step 1: Regenerate Xcode project**

Run: `cd ios/Astral && xcodegen generate`

Expected: Project generated successfully. (XcodeGen auto-discovers Swift files in package directories, but verify the project opens cleanly.)

- [ ] **Step 2: Full clean build**

Run: `cd ios/Astral && xcodebuild clean build -scheme Astral -sdk iphonesimulator -destination 'platform=iOS Simulator,id=8FF2D1FB-E342-4E2A-BFB6-F608B18609DF' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED with 0 errors. Warnings are acceptable.

- [ ] **Step 3: Commit any project file changes**

```bash
git add ios/Astral/project.yml ios/Astral/Astral.xcodeproj/
git commit -m "[ios] regenerate Xcode project with new download resilience files"
```

---

## Execution Summary

| Task | What it delivers |
|------|-----------------|
| 1 | DownloadState enum + model migrations |
| 2 | FanficDownloadService (extracted, atomic, guarded) |
| 3 | Hardened ChapterDownloadService (atomic, validated) |
| 4 | **Critical fix:** Fanfic reader loads local files first |
| 5 | Comic reader validates local pages, shows offline state |
| 6 | OrphanCleanupService reconciles disk on launch |
| 7 | ImageCacheService + CachedAsyncImage for offline thumbnails |
| 8 | BackgroundDownloadSession for bulk comic downloads |
| 9 | Last-synced timestamp in library UI |
| 10 | Per-chapter download status indicators |
| 11 | Final build verification |
