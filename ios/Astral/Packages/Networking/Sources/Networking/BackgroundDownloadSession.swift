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

    private struct TaskInfo {
        let comicId: UUID
        let chapterId: UUID
        let pageNumber: Int
        let destinationDir: URL
        var retryCount: Int = 0
    }

    private var taskMap: [Int: TaskInfo] = [:]
    private let lock = NSLock()

    /// Completion handler provided by the system for background URL session events
    public var systemCompletionHandler: (() -> Void)?

    /// Published progress per chapter
    @MainActor public var chapterProgress: [UUID: (completed: Int, total: Int)] = [:]

    /// Callbacks when chapters finish (called on main actor)
    @MainActor public var onChapterComplete: ((UUID, UUID) -> Void)?  // (comicId, chapterId)
    @MainActor public var onChapterFailed: ((UUID, UUID, String) -> Void)?  // (comicId, chapterId, error)

    private override init() {
        super.init()
        _ = session  // Touch to reconnect on relaunch
    }

    // MARK: - Enqueue Downloads

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

        Task { @MainActor in
            if var progress = self.chapterProgress[info.chapterId] {
                progress.completed += 1
                self.chapterProgress[info.chapterId] = progress

                if progress.completed >= progress.total {
                    self.onChapterComplete?(info.comicId, info.chapterId)
                    self.chapterProgress.removeValue(forKey: info.chapterId)
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
        didCompleteWithError error: (any Error)?
    ) {
        guard let error = error else { return }

        lock.lock()
        guard var info = taskMap[task.taskIdentifier] else {
            lock.unlock()
            return
        }
        taskMap.removeValue(forKey: task.taskIdentifier)
        lock.unlock()

        let nsError = error as NSError
        if info.retryCount < maxRetries,
           let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            info.retryCount += 1
            let newTask = self.session.downloadTask(withResumeData: resumeData)
            lock.lock()
            taskMap[newTask.taskIdentifier] = info
            lock.unlock()
            newTask.resume()
            AstralLogger.info("Background download: retrying page \(info.pageNumber) (attempt \(info.retryCount))", context: "BGDownload")
        } else {
            Task { @MainActor in
                let msg = "Page \(info.pageNumber) failed after \(info.retryCount + 1) attempts"
                self.onChapterFailed?(info.comicId, info.chapterId, msg)
                self.chapterProgress.removeValue(forKey: info.chapterId)
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
