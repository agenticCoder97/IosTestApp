import XCTest

/// Tests for the comic reading flow: library → detail → reader → dismiss.
final class ComicFlowTests: BaseTestCase {

    func testOpenComicDetailFromLibrary() {
        let library = ComicLibraryScreen(app: app)
        library.assertVisible()

        // Tap the first comic card
        let detail = library.tapFirstStory()

        // Verify detail view shows chapter list
        detail.chaptersTab.assertExists()
    }

    func testOpenComicReaderFromDetail() {
        let library = ComicLibraryScreen(app: app)
        let detail = library.tapFirstStory()

        // Tap the first chapter
        detail.tapChapter(1)

        // Verify comic reader is visible (back button appears)
        let reader = ComicReaderScreen(app: app)
        reader.assertVisible()
    }

    func testDismissComicReader() {
        let library = ComicLibraryScreen(app: app)
        let detail = library.tapFirstStory()
        detail.tapChapter(1)

        let reader = ComicReaderScreen(app: app)
        reader.assertVisible()

        // Dismiss the reader
        reader.dismiss()

        // Should be back on the detail view
        detail.chaptersTab.assertExists()
    }

    func testComicReaderScrollInWebtoonMode() {
        let library = ComicLibraryScreen(app: app)
        let detail = library.tapFirstStory()
        detail.tapChapter(1)

        let reader = ComicReaderScreen(app: app)
        reader.assertVisible()

        // Scroll down in the reader
        reader.scrollDown()
        reader.scrollDown()

        // Reader should still be visible (didn't crash or dismiss)
        reader.assertVisible()

        captureScreenshot(named: "comic-reader-scrolled")
    }
}
