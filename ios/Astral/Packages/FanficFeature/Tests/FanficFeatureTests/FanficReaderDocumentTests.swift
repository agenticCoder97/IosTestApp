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

@Suite("Imported formatting")
struct FanficTextMarksTests {

    @Test("imported stories keep intentional line breaks; plain text joins them")
    func lineBreaksFollowSource() {
        let text = "Guests:\n  Granger\n Pansy\n\nNext paragraph."
        #expect(FanficReaderDocument.paragraphs(in: text, keepsLineBreaks: true) == ["Guests:\nGranger\nPansy", "Next paragraph."])
        #expect(FanficReaderDocument.paragraphs(in: text) == ["Guests: Granger Pansy", "Next paragraph."])
    }

    @Test("marks never reach plain text, word counts or scene breaks")
    func marksAreInvisibleToPlainText() {
        let italic = "\u{E000}Not\u{E001} again"
        #expect(FanficTextMarks.plain(italic) == "Not again")
        let document = FanficReaderDocument(text: "\u{E004}\u{E000}* * *\u{E001}\n\n\u{E002}Bold\u{E003} words here", keepsLineBreaks: true)
        #expect(document.sceneBreaks == [0])
        #expect(document.wordCount == 6)
    }

    @Test("styled text drops the marks and keeps every character")
    func styledTextKeepsCharacters() {
        let styled = FanficTextMarks.styled("\u{E004}A \u{E000}quiet\u{E001} \u{E002}word\u{E003}", font: .system, size: 16)
        #expect(String(styled.characters) == "A quiet word")
        #expect(styled.runs.count == 4)
        #expect(FanficTextMarks.isCentered("\u{E004}Centred"))
    }

    @Test("a paragraph of marks alone is not kept as an empty line")
    func markOnlyParagraphsDropped() {
        #expect(FanficReaderDocument.paragraphs(in: "One\n\n\u{E000}\u{E001}\n\nTwo", keepsLineBreaks: true) == ["One", "Two"])
    }
}

@Suite("Mark trimming")
struct FanficMarkTrimmingTests {
    @Test("spaces just inside edge marks are removed; inner spacing is kept")
    func trimsInsideEdgeMarks() {
        #expect(FanficTextMarks.trimmed("  \u{E000} How is it difficult? \u{E001} ") == "\u{E000}How is it difficult?\u{E001}")
        #expect(FanficTextMarks.trimmed("A \u{E000}quiet\u{E001} word") == "A \u{E000}quiet\u{E001} word")
        #expect(FanficTextMarks.trimmed(" \u{E000} \u{E001} ").isEmpty)
    }
}
