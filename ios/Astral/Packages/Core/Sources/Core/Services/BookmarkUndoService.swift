import Foundation
import SwiftData
import Observation

@MainActor @Observable
public final class BookmarkUndoService {
    public static let shared = BookmarkUndoService()
    public private(set) var message: String?
    public private(set) var canUndo = false
    private var restore: (() throws -> Void)?
    private var expiry: Task<Void, Never>?
    private init() {}
    public func delete(_ bookmark: LocalBookmark, context: ModelContext) {
        let id = bookmark.id, type = bookmark.contentType, story = bookmark.storyId, number = bookmark.chapterNumber
        let page = bookmark.pageNumber, fraction = bookmark.scrollPercent, note = bookmark.note, created = bookmark.createdAt
        let word = bookmark.wordOffset, text = bookmark.selectedText, heading = bookmark.heading
        do {
            try context.save()
            context.delete(bookmark)
            try context.save()
            restore = {
                let exists: Bool
                if type == "comic" { exists = try !context.fetch(FetchDescriptor<LocalComic>(predicate: #Predicate { $0.id == story })).isEmpty }
                else { exists = try !context.fetch(FetchDescriptor<LocalFanfic>(predicate: #Predicate { $0.id == story })).isEmpty }
                guard exists else { throw CocoaError(.fileNoSuchFile) }
                let restored = LocalBookmark(id: id, contentType: type, storyId: story, chapterNumber: number, pageNumber: page, scrollPercent: fraction, note: note, createdAt: created, wordOffset: word, selectedText: text, heading: heading)
                context.insert(restored); try context.save()
            }
            message = "Bookmark removed"; canUndo = true
        } catch { context.rollback(); message = "Bookmark could not be removed: " + error.localizedDescription; canUndo = false }
        // The banner sits over every tab, so it leaves on its own like other undo toasts.
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
    public func undo() {
        do { try restore?(); dismiss() }
        catch { message = "Bookmark could not be restored: " + error.localizedDescription }
    }
    public func dismiss() { expiry?.cancel(); expiry = nil; message = nil; canUndo = false; restore = nil }
}
