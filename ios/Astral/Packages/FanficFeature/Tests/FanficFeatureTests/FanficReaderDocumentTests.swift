import Testing
@testable import FanficFeature

@Suite("FanficReaderDocument paragraphs")
struct FanficReaderDocumentTests {

    @Test("blank lines separate paragraphs and single breaks are joined")
    func blankLinesSeparateParagraphs() {
        let text = "First line\nstill first.\n\nSecond.\n \nThird."
        #expect(FanficReaderDocument.paragraphs(in: text) == ["First line still first.", "Second.", "Third."])
    }

    @Test("Windows line endings split like Unix ones")
    func windowsLineEndings() {
        let text = "One.\r\n\r\nTwo.\r\n\r\nThree."
        #expect(FanficReaderDocument.paragraphs(in: text) == ["One.", "Two.", "Three."])
    }

    @Test("a file with one paragraph per line does not become one block")
    func onePerLineFallsBackToLines() {
        let text = "One.\nTwo.\nThree."
        #expect(FanficReaderDocument.paragraphs(in: text) == ["One.", "Two.", "Three."])
    }

    @Test("word offsets and scene breaks follow the split paragraphs")
    func offsetsFollowParagraphs() {
        let document = FanficReaderDocument(text: "Alpha beta.\r\n\r\n* * *\r\n\r\nGamma.")
        #expect(document.paragraphs.count == 3)
        #expect(document.wordOffsets == [0, 2, 5])
        #expect(document.sceneBreaks == [1])
    }
}
