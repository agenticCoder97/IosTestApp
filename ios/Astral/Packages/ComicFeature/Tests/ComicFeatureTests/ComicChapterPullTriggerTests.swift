import Testing
@testable import ComicFeature

@Suite("ComicChapterPullTrigger")
struct ComicChapterPullTriggerTests {

    @Test("full pull fires even before arm delay completes")
    func fullPullFiresBeforeArmDelayCompletes() {
        #expect(ComicChapterPullTrigger.shouldFire(progress: 1.0, hasTriggered: false))
    }

    @Test("partial pull does not fire")
    func partialPullDoesNotFire() {
        #expect(!ComicChapterPullTrigger.shouldFire(progress: 0.99, hasTriggered: false))
    }

    @Test("already triggered pull does not fire again")
    func alreadyTriggeredPullDoesNotFireAgain() {
        #expect(!ComicChapterPullTrigger.shouldFire(progress: 1.0, hasTriggered: true))
    }
}
