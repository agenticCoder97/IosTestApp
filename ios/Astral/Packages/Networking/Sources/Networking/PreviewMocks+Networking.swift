import Foundation
import Core

// DTO-level mock data for Xcode Previews in reader views.
// Core model mocks live in Core/PreviewMocks.swift.
@MainActor
extension PreviewMocks {

    // MARK: - Sample Pages (for ComicReaderView)

    /// 5 pages with varied aspect ratios to exercise the ComicPageView layout.
    public static let samplePages: [PageResponse] = [
        PageResponse(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!,
            pageNumber: 1,
            filePath: "/comics/solo-leveling/ch1/p001.jpg",
            sourceUrl: nil,
            widthPx: 800,
            heightPx: 1200
        ),
        PageResponse(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000002")!,
            pageNumber: 2,
            filePath: "/comics/solo-leveling/ch1/p002.jpg",
            sourceUrl: nil,
            widthPx: 800,
            heightPx: 1200
        ),
        PageResponse(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000003")!,
            pageNumber: 3,
            filePath: "/comics/solo-leveling/ch1/p003.jpg",
            sourceUrl: nil,
            widthPx: 1600,
            heightPx: 900  // wide splash page
        ),
        PageResponse(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000004")!,
            pageNumber: 4,
            filePath: "/comics/solo-leveling/ch1/p004.jpg",
            sourceUrl: nil,
            widthPx: 800,
            heightPx: 1200
        ),
        PageResponse(
            id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000005")!,
            pageNumber: 5,
            filePath: "/comics/solo-leveling/ch1/p005.jpg",
            sourceUrl: nil,
            widthPx: 800,
            heightPx: 1200
        ),
    ]

    // MARK: - Sample Fanfic Chapter Content (for FanficReaderView)

    public static let sampleFanficChapterContent: String = """
    The rain hadn't stopped for three days.

    Mira stood at the window, her fingers tracing the rivulets that raced each other down the glass. The city below was a smear of amber and grey, umbrellas moving like scattered beetles across the cobblestones. She'd been in Hogwarts for six years and had never quite gotten used to the way the Scottish weather simply decided, with great conviction, to be miserable.

    "You're blocking the light," said a voice behind her.

    She didn't turn around. She already knew who it was — there was only one person who used the restricted section at this hour, and he was the reason she was here instead of in her dormitory like a sensible person.

    "There isn't any light," she said. "It's raining."

    A pause. The scratch of a quill. Then: "Fair point."

    Theo Nott had a talent for conceding arguments he'd never intended to start. She'd catalogued at least a dozen instances over the past four months of working in such close proximity that she could tell his mood by the angle of his handwriting. It was, she thought, a deeply alarming thing to know about someone.

    She turned away from the window.

    He was hunched over the far table, surrounded by books that had clearly been there long enough to form opinions about the arrangement. His robes were rumpled in the specific way that meant he'd been here since before dinner. The dark circles under his eyes had taken up permanent residence sometime around October.

    "You haven't eaten," she said.

    "I'm not hungry."

    "That isn't what I asked."

    He looked up then. In the low lamplight his eyes were the colour of old parchment, and she had the unsettling thought — not for the first time — that he looked like someone who had been interrupted in the middle of becoming something else entirely.

    "There's a difference," she added, softer than she'd intended.

    Something shifted in his expression. It was there for only a moment, that thing she couldn't name, before he looked back down at his notes.

    "I'll eat later," he said.

    She crossed the room and set half her sandwich on the corner of his table. He didn't acknowledge it. She sat down across from him and opened her own book.

    The rain continued. The candles flickered. Somewhere in the castle a clock chimed the late hour.

    Mira read four pages without taking in a single word.
    """

    public static let sampleFanficChapterResponse: FanficChapterResponse = FanficChapterResponse(
        id: UUID(uuidString: "BBBB0000-0000-0000-0000-000000000001")!,
        chapterNumber: 1.0,
        title: "Chapter 1: First Encounter",
        content: sampleFanficChapterContent,
        wordCount: 4_800,
        sourceUrl: "https://archiveofourown.org/works/12345678/chapters/11111111",
        scrapeStatus: "scraped",
        createdAt: Date(timeIntervalSinceNow: -60 * 60 * 24 * 10)
    )
}
