import Foundation
import Testing
@testable import ComicFeature

@Suite("ComicReaderPageSource")
struct ComicReaderPageSourceTests {

    @Test("local files drive page count when present")
    func localFilesDrivePageCountWhenPresent() {
        let urls = [
            URL(fileURLWithPath: "/tmp/page_0001.jpg"),
            URL(fileURLWithPath: "/tmp/page_0002.jpg"),
            URL(fileURLWithPath: "/tmp/page_0003.jpg"),
        ]

        let source = ComicReaderPageSource(networkPageCount: 0, localPageURLs: urls)

        #expect(source.usesLocalPages)
        #expect(source.pageCount == 3)
    }

    @Test("network pages drive page count when no local files exist")
    func networkPagesDrivePageCountWhenNoLocalFilesExist() {
        let source = ComicReaderPageSource(networkPageCount: 12, localPageURLs: nil)

        #expect(!source.usesLocalPages)
        #expect(source.pageCount == 12)
    }
}
