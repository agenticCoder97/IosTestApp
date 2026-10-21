#if DEBUG
import Foundation
import SwiftData
import UIKit

/// Opt-in simulator corpus for manual reader verification. Never enabled on an
/// ordinary launch. Includes fractional numbering, a long strip and a one-page chapter.
@MainActor
public enum DevelopmentReaderCorpus {
    public static func installIfRequested(context: ModelContext) throws {
        guard CommandLine.arguments.contains("--reader-fixtures") else { return }
        let id = UUID(uuidString: "A57A0000-0000-4000-8000-000000000001")!
        guard try context.fetch(FetchDescriptor<LocalComic>(predicate: #Predicate { $0.id == id })).isEmpty else { return }
        let story = LocalComic(id: id, title: "Reader verification sample", sourceKey: "local", totalChapters: 3, status: "complete", isDownloaded: true, seenTotalChapters: 3)
        story.completionStatus = "complete"
        context.insert(story)
        for (order, number) in [1.0, 2.5, 10.0].enumerated() {
            let chapter = LocalComicChapter(id: UUID(), comicId: id, chapterNumber: number, title: "Sample \(number.formatted())", totalPages: order == 1 ? 1 : 3, isDownloaded: true, scrapeStatus: "scraped")
            let directory = "comics/\(id)/\(chapter.id)"
            let target = URL.documentsDirectory.appendingPathComponent(directory)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for page in 1...chapter.totalPages {
                let size = CGSize(width: 600, height: order == 0 && page == 2 ? 2400 : 800)
                let renderer = UIGraphicsImageRenderer(size: size)
                let image = renderer.image { ctx in
                    UIColor(white: page.isMultiple(of: 2) ? 0.9 : 0.75, alpha: 1).setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                    let label = "CHAPTER \(number.formatted())\nPAGE \(page)\n\nManual verification fixture"
                    (label as NSString).draw(in: CGRect(x: 40, y: 60, width: 520, height: 500), withAttributes: [.font: UIFont.systemFont(ofSize: 42, weight: .bold), .foregroundColor: UIColor.black])
                    for y in stride(from: 600, to: Int(size.height), by: 300) {
                        ("PAGE \(page) · offset \(y)" as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
                    }
                }
                try image.pngData()!.write(to: target.appendingPathComponent(String(format: "page_%04d.png", page)))
            }
            chapter.localPagesPath = directory; chapter.downloadStatus = .complete; chapter.comic = story
            context.insert(chapter)
        }
        try context.save()
    }
}
#endif
