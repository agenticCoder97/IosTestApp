# Offline Download Resilience — Full Design Spec

**Date:** 2026-04-11  
**Scope:** Hybrid approach — hardened per-feature download services + background URLSession for bulk comic downloads  
**Goal:** Downloaded content reliably works offline; graceful degradation when backend is down

---

## 1. Download State Machine

### New Enum (Core package)

```swift
public enum DownloadState: String, Codable {
    case none          // Never downloaded
    case queued        // Waiting to start
    case downloading   // In progress
    case failed        // Failed, can retry
    case complete      // Verified on disk
}
```

### Model Changes

**LocalComicChapter** additions:
- `downloadState: DownloadState` (default `.none`, replaces `isDownloaded`)
- `downloadedAt: Date?`
- `downloadSizeBytes: Int64?`
- `downloadError: String?`

**LocalFanficChapter** additions:
- `downloadState: DownloadState` (default `.none`, replaces `isDownloaded`)
- `downloadedAt: Date?`
- `downloadError: String?`

**LocalComic / LocalFanfic** additions:
- `lastSyncedAt: Date?` — set on each successful library fetch
- Computed `isFullyDownloaded: Bool` → all chapters have `downloadState == .complete`

**Backward compatibility:**
- Existing `isDownloaded: Bool` becomes computed: `downloadState == .complete`
- Existing `localPagesPath` / `localTextPath` remain as the source-of-truth for file locations
- Remove deprecated fields in next release cycle

### Fanfic File Path Fix

**Bug:** `ch\(Int(chapter.chapterNumber)).txt` truncates decimals (ch3.5 → ch3).

**Fix:** Use `String(format: "%.1f", chapter.chapterNumber)` → `ch3.5.txt`

**Migration:** On first launch, scan `Documents/fanfics/` and rename any `chN.txt` where the model has a non-integer chapter number. Run inside `OrphanCleanupService.migrateChapterPaths()`.

---

## 2. Atomic Downloads & Cleanup

### Atomic Write Pattern

All downloads use a two-phase commit:

1. **Write to temp:** `tmp/astral-downloads/{jobId}/`
2. **Validate:** Check file integrity (magic bytes for images, non-empty for text)
3. **Atomic move:** `FileManager.moveItem(at: tempPath, to: finalPath)`
4. **Persist state:** Update SwiftData model, save context
5. **On failure at any step:** Delete temp directory, set `downloadState = .failed`, record error

If `modelContext.save()` fails after the atomic move, delete the moved files to maintain consistency.

### Comic Chapter Download (Atomic)

```
1. Set downloadState = .queued
2. Create temp dir: tmp/astral-downloads/{chapterId}/
3. Fetch page URLs from API (JSON)
4. Set downloadState = .downloading
5. Download all pages into temp dir (task group, max 4 concurrent)
6. Validate each file:
   - Size > 1KB
   - First bytes match JPEG (FF D8 FF) or PNG (89 50 4E 47) magic
7. If ALL valid:
   - Move temp dir → Documents/comics/{comicId}/{chapterId}/
   - Set localPagesPath, downloadState = .complete, downloadedAt = .now
   - Accumulate file sizes into downloadSizeBytes
   - modelContext.save() — if fails, delete moved dir, set .failed
8. If ANY invalid:
   - Delete temp dir
   - Set downloadState = .failed
   - Set downloadError = "Page X failed validation"
```

### Fanfic Chapter Download (Atomic)

```
1. Set downloadState = .queued
2. Fetch chapter content from API
3. Set downloadState = .downloading
4. Validate: content non-nil and non-empty
5. Write to temp: tmp/astral-downloads/{fanficId}_ch{number}.txt (atomically: true)
6. Move to final: Documents/fanfics/{fanficId}/ch{number}.txt
7. Set localTextPath, downloadState = .complete, downloadedAt = .now
8. modelContext.save() — if fails, delete file, set .failed
```

### Concurrent Download Guard

`ChapterDownloadService` and `FanficDownloadService` maintain:

```swift
private var activeDownloads: Set<UUID> = []

func downloadChapter(_ chapter: ...) async {
    guard !activeDownloads.contains(chapter.id) else { return }
    activeDownloads.insert(chapter.id)
    defer { activeDownloads.remove(chapter.id) }
    // ... download logic
}
```

### Disk Space Check

Before starting any download:

```swift
let availableBytes = try FileManager.default
    .attributesOfFileSystem(forPath: documentsDir.path)[.systemFreeSize] as? Int64 ?? 0

// Comic: estimate ~500KB per page * totalPages
// Fanfic: negligible (text)
guard availableBytes > estimatedSize + (50 * 1024 * 1024) else {  // 50MB buffer
    chapter.downloadState = .failed
    chapter.downloadError = "Not enough storage space"
    return
}
```

### Orphan Cleanup Service (runs on app launch)

```swift
final class OrphanCleanupService {
    static func cleanOnLaunch(modelContext: ModelContext) {
        // 1. Delete tmp/astral-downloads/ entirely (leftover from killed downloads)
        // 2. Scan Documents/comics/ directories
        //    - For each chapterId dir: check SwiftData has downloadState == .complete
        //    - If not found or state != .complete → delete directory
        // 3. Scan Documents/fanfics/ files
        //    - For each .txt file: check matching chapter has downloadState == .complete
        //    - If not found or state != .complete → delete file
        // 4. Check SwiftData records with downloadState == .complete
        //    - Verify file/dir exists on disk
        //    - If missing → reset downloadState to .none, clear localPagesPath/localTextPath
        // 5. Migrate fanfic chapter paths (Int → Double naming fix)
    }
}
```

---

## 3. Fanfic Reader Offline Fix

### Current Bug

`FanficReaderView.loadChapter()` always calls the network API. Downloaded local `.txt` files are never read. Offline fanfic reading is completely broken.

### Fix: Local-First Loading

```swift
private func loadChapter() async {
    isLoading = true
    defer { isLoading = false }

    // 1. Try local file first
    if let localPath = currentChapter.localTextPath {
        let url = documentsDir.appendingPathComponent(localPath)
        if let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
            chapterContent = content
            calculateScrollTarget()
            return
        } else {
            // File missing or corrupt — reset state
            currentChapter.downloadState = .none
            currentChapter.localTextPath = nil
            try? modelContext.save()
        }
    }

    // 2. Try network
    do {
        let response: FanficChapterResponse = try await APIClient.shared.request(
            .fanficChapter(fanficId: fanfic.id, chapterId: currentChapter.id)
        )
        guard !Task.isCancelled else { return }
        chapterContent = response.content ?? ""
        calculateScrollTarget()
    } catch {
        // 3. Offline and not downloaded
        chapterContent = ""
        offlineError = true  // drives UI state
    }
}
```

### Comic Reader Hardening

```swift
private func loadPages() async {
    // 1. Try local files
    if let urls = ChapterDownloadService.shared.localPageURLs(for: chapter) {
        if urls.count == chapter.totalPages {
            localPageURLs = urls
            return
        } else {
            // Mismatch — partial/corrupt download
            chapter.downloadState = .failed
            chapter.downloadError = "Expected \(chapter.totalPages) pages, found \(urls.count)"
            try? modelContext.save()
        }
    }

    // 2. Try network
    do {
        let pageResponse = try await APIClient.shared.request(...)
        pages = pageResponse
    } catch {
        // 3. Offline banner
        offlineError = true
    }
}
```

### Offline UI States

**When offline + not downloaded:**
- Full-screen placeholder: cloud.slash icon
- "This chapter isn't downloaded"
- "Connect to download for offline reading" (muted caption)

**When offline + downloaded:**
- Reads normally from local files
- Small green pill: "Reading offline"

---

## 4. Background Download Session (Comics)

### When It Activates

Only for "Download All Chapters" on a comic (bulk: potentially 100+ chapters, 1000+ images). Single-chapter downloads and all fanfic downloads use regular async/await.

### BackgroundDownloadSession (Networking package)

```swift
final class BackgroundDownloadSession: NSObject, URLSessionDownloadDelegate {
    static let shared = BackgroundDownloadSession()
    
    private let sessionID = "com.astral.background-downloads"
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: sessionID)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // Maps taskIdentifier → DownloadTaskInfo (chapterId, pageNumber, comicId)
    private var taskMap: [Int: DownloadTaskInfo] = [:]
    
    // Resume data storage for retries
    private var resumeDataStore: [UUID: Data] = [:]  // chapterId+pageNum → resumeData
    
    // Progress publisher
    @Published var activeDownloads: [UUID: ChapterDownloadProgress] = [:]
    
    // Completion handler for background URL session events
    var backgroundCompletionHandler: (() -> Void)?
}
```

### Download All Flow

```
1. User taps "Download All" on ComicDetailView
2. ChapterDownloadService.downloadAllChapters(background: true)
3. For each chapter with downloadState != .complete:
   a. Set downloadState = .queued
   b. Fetch page URLs via regular API call (small JSON, fast)
   c. For each page URL:
      - Create URLSessionDownloadTask via BackgroundDownloadSession
      - Store mapping: taskIdentifier → (comicId, chapterId, pageNumber)
   d. Set downloadState = .downloading
4. Background session manages all tasks
5. Delegate callbacks handle completion:
   - didFinishDownloadingTo: validate + move to staging
   - didCompleteWithError: store resume data, retry up to 3x
6. When all pages for a chapter complete:
   - Atomic move staging dir → final dir
   - Update SwiftData state
7. When all chapters complete → comic.lastSyncedAt = .now
```

### App Lifecycle Integration

**AppDelegate / App struct:**

```swift
func application(_ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void) {
    BackgroundDownloadSession.shared.backgroundCompletionHandler = completionHandler
}
```

**Delegate callback:**

```swift
func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
        self.backgroundCompletionHandler?()
        self.backgroundCompletionHandler = nil
    }
}
```

### Resume & Retry

```swift
func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error = error else { return }
    let nsError = error as NSError
    
    if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
        let info = taskMap[task.taskIdentifier]
        resumeDataStore[info.pageId] = resumeData
        
        if info.retryCount < 3 {
            // Retry with resume data
            let newTask = session.downloadTask(withResumeData: resumeData)
            taskMap[newTask.taskIdentifier] = info.incrementRetry()
            newTask.resume()
        } else {
            // Give up on this chapter
            markChapterFailed(info.chapterId, error: "Page \(info.pageNumber) failed after 3 retries")
        }
    }
}
```

### Progress Reporting

```swift
struct ChapterDownloadProgress {
    let chapterId: UUID
    let totalPages: Int
    var completedPages: Int
    var failedPages: Int
    var percent: Double { Double(completedPages) / Double(totalPages) }
}
```

UI observes `BackgroundDownloadSession.shared.activeDownloads` to show per-chapter and overall progress.

---

## 5. Thumbnail & Cover Image Cache

### ImageCacheService (DesignSystem or Core package)

Lightweight LRU disk cache for thumbnails and cover images.

```swift
actor ImageCacheService {
    static let shared = ImageCacheService()
    
    private let cacheDir: URL  // Library/Caches/thumbnails/
    private let maxDiskBytes: Int64 = 200 * 1024 * 1024  // 200MB limit
    
    func cachedImage(for remotePath: String) -> URL?
    func cacheImage(data: Data, for remotePath: String) async throws -> URL
    func evictIfNeeded() async  // LRU eviction when over limit
}
```

**Cache key:** SHA256 hash of the remote path → `{hash}.jpg`

**Usage in StoryThumbnail / cover views:**

```swift
// 1. Check disk cache
if let localURL = await ImageCacheService.shared.cachedImage(for: path) {
    return Image(uiImage: UIImage(contentsOfFile: localURL.path)!)
}
// 2. Download from network
let data = try await URLSession.shared.data(from: fullURL).0
let localURL = try await ImageCacheService.shared.cacheImage(data: data, for: path)
return Image(uiImage: UIImage(data: data)!)
// 3. If both fail (offline, no cache): show placeholder
return Image(systemName: "book.closed.fill")
```

**Eviction:** When total cache exceeds 200MB, delete oldest-accessed files until under 150MB.

**Offline benefit:** Library shows cached thumbnails even when backend is unreachable. No more blank cover art.

---

## 6. UI Indicators & Last Synced

### Per-Chapter Download Status (Detail Views)

Each chapter row shows:
- No icon → not downloaded (`.none`)
- Spinner → downloading (`.queued` / `.downloading`)
- Green checkmark → downloaded (`.complete`)
- Red exclamation → failed (`.failed`) — tappable to retry

### Library-Level Indicators

- `arrow.down.circle.fill` (green) — all chapters downloaded
- `arrow.down.circle` (muted) — some or no chapters downloaded
- Small badge showing download count: "8/12"

### "Last Synced" Display

In library header or pull-to-refresh area:
- "Updated just now" / "Updated 5 min ago" / "Updated 2 hours ago"
- If never synced: "Never synced"
- Uses `RelativeDateTimeFormatter` on `comic.lastSyncedAt` / `fanfic.lastSyncedAt`

### Download Manager Sheet (New)

Accessible from a toolbar button when any downloads are active:

```
┌─────────────────────────────────────┐
│ Downloads                     Done  │
├─────────────────────────────────────┤
│ Solo Leveling                       │
│  Ch 45: ████████░░ 78%             │
│  Ch 46: queued                      │
│  Ch 47: queued                      │
├─────────────────────────────────────┤
│ 2/12 chapters complete              │
│ [Pause All]  [Cancel]               │
└─────────────────────────────────────┘
```

---

## 7. FanficDownloadService (New)

Extract inline download logic from `FanficDetailView` into a proper service:

```swift
@MainActor
final class FanficDownloadService {
    static let shared = FanficDownloadService()
    
    private var activeDownloads: Set<UUID> = []
    
    func downloadAllChapters(
        fanfic: LocalFanfic,
        chapters: [LocalFanficChapter],
        modelContext: ModelContext,
        progress: @escaping (Int, Int) -> Void
    ) async
    
    func downloadChapter(
        fanfic: LocalFanfic,
        chapter: LocalFanficChapter,
        modelContext: ModelContext
    ) async
    
    func deleteAllChapters(
        fanfic: LocalFanfic,
        chapters: [LocalFanficChapter],
        modelContext: ModelContext
    )
    
    func deleteChapter(
        chapter: LocalFanficChapter,
        modelContext: ModelContext
    )
}
```

Follows same atomic pattern as `ChapterDownloadService`. Uses regular async/await (text downloads are small and fast).

---

## 8. Error Handling Summary

| Scenario | Behavior |
|----------|----------|
| Network down during download | Set `.failed`, record error, cleanup temp |
| Disk full | Pre-check fails, set `.failed`, error = "Not enough storage" |
| App killed mid-download (regular) | Temp files cleaned on next launch by OrphanCleanupService |
| App killed mid-download (background) | OS resumes tasks, delegate handles on relaunch |
| Corrupted file downloaded | Magic byte validation fails, set `.failed`, cleanup |
| SwiftData save fails | Delete moved files, set `.failed` |
| File missing but state says complete | OrphanCleanupService resets to `.none` on launch |
| Concurrent download attempt | Guard via `activeDownloads` set, skip duplicate |
| API returns nil content (fanfic) | Set `.failed`, error = "Empty chapter content" |
| 3 retries exhausted (background) | Set `.failed`, error = "Failed after 3 retries" |

---

## 9. Package Placement

| Component | Package | Reason |
|-----------|---------|--------|
| `DownloadState` enum | Core | Used by models in Core |
| `OrphanCleanupService` | Core | Needs SwiftData models |
| `BackgroundDownloadSession` | Networking | URLSession lives here |
| `ImageCacheService` | Core | Shared across features |
| `ChapterDownloadService` (hardened) | ComicFeature | Comic-specific logic |
| `FanficDownloadService` (new) | FanficFeature | Fanfic-specific logic |
| `CachedAsyncImage` view | DesignSystem | Reusable UI component |
| Download progress UI | Per-feature | Feature-specific views |

---

## 10. Migration Plan

On first app launch after update:

1. Map existing `isDownloaded == true` → `downloadState = .complete`
2. Map existing `isDownloaded == false` → `downloadState = .none`
3. Rename fanfic files with integer names to decimal format where needed
4. Run OrphanCleanupService to reconcile disk vs SwiftData
5. All existing downloads remain valid — no re-download needed
