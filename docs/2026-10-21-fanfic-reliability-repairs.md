# Fanfic reliability repairs

21 October 2026. Follow-up to the device-first rebuild, after the user reported choppy fanfic scrolling, missing thumbnails and FFNet imports containing only one chapter.

## Scope and preservation

This pass repairs those three functions. Pull-to-next/previous at the actual content boundary remains. No end-of-chapter panel or transition page is added. Existing reader typography, themes, passage bookmarks, chapter picker, named navigation, resume and explicit completion actions remain. The reading activity heat map and its day drill-down remain in Settings → Reading history; this pass does not reorganize that route or remove stats.

The user approved cover-grid/library sections and tag browsing as a later UI direction. Those screens are not implemented in this reliability pass. NSFW source testing remains excluded. No hosted backend is required and no database schema changes are introduced.

## Scrolling

- Prepare normalized paragraphs, scene breaks and word offsets once per chapter on a dedicated actor. File reads move off the main actor too.
- Capture exact scrolling position in a reference object without publishing every offset to the reader or SwiftData. Only the small percentage readout observes integer percentage changes.
- Persist progress at existing lifecycle and chapter-transition boundaries. Passage bookmarks capture the current fraction directly. Existing paragraph/pixel/layout-signature resume behavior remains.
- Leave the shared pull observer and its release-gated state machine unchanged.
- Open a chapter at the actual top when its paragraph anchor is zero, keeping its heading and first lines below the overlaid toolbar. The controller uses the actual adjusted-content-inset top rather than a raw zero offset. Start chapter over uses the same physical reset. Compatible saved pixel offsets still restore afterward.

This removes code-backed sources of repeated work. It is not a claim of a measured frame-rate improvement on the user's phone.

## Thumbnails

- Extract FFNet story artwork where the source supplies it. The shared importer stores the image on the phone.
- Restore the old backend's single-fandom Wikipedia lookup on the device. Existing library entries with missing or obsolete server-relative images are repaired when Library appears. Crossovers, RPF and ambiguous fandom matches retain a placeholder rather than receiving unrelated artwork.
- Download and validate image data, downsample to at most 600 pixels, and save a JPEG under Documents/fanficCovers. The database uses a document-relative path, so same-schema backups can restore the image on another installation.
- Retain existing readable local artwork. Removing saved chapter text keeps the separate cover; permanent story deletion removes it. Artwork provenance is recorded under the backed-up reading metadata namespace.
- Retry a previously missing cover immediately when its fandom or artwork metadata changes; the five-minute failure cooldown applies only to the same request.
- Lookup transmits a fandom candidate to Wikipedia, not the story title/text or browser cookies. Thumbnail failures do not fail the story import. The existing bounded image cache remains available for other remote images.

The source-work image API is documented at [MediaWiki PageImages](https://www.mediawiki.org/wiki/Extension:PageImages#API). Returned Wikimedia upload and thumbnail hosts are accepted; explicit image-license selection allows the source-work images that the API otherwise omits by default. Artwork is source-work artwork, not a claim that the author supplied a cover for every AO3 work.

## FFNet completeness

- Detect chapter numbers from desktop/mobile selectors, URL-valued options, chapter-count metadata (including mobile “Ch N of M”) and Next links, including onclick navigation. Capture the mobile category breadcrumb as fandom metadata for local cover lookup.
- Do not silently default an unrecognized mobile page to one chapter. A desktop one-shot needs actual metadata and no chapter navigation. Otherwise acquisition needs a count or a Next chain, or produces an actionable chapter-list error.
- When the source provides only Next links, acquire sequentially until that chain ends. Validate chapter identity, consistency and size limits before committing the complete work.
- Wait for the chapter document to finish parsing before extraction, while continuing to ignore unrelated resources that may still be loading. Existing checkpoint/retry and protected-source error behavior remains.

## Verification

- FFNet WebKit extraction checks passed nine cases: duplicate desktop dropdowns, mobile count metadata, mobile breadcrumb plus abbreviated count, anchor Next chains, onclick Next chains, URL-valued options, verified one-shots, unknown mobile rejection and contradictory count rejection.
- A macOS WebKit/SwiftData harness exercised production native acquisition, parsing, file writing, identity matching and model commit with fixture navigation and temporary storage roots. Passed a complete three-chapter import and Next-link-only reimport; retained identities, bookmark, favourite and 42% chapter-two progress. An incomplete chapter-two response failed without replacing the saved work. Artwork was isolated from this harness. These are fixture results, not live FFNet acceptance.
- Actual thumbnail acquisition passed against Wikipedia/Wikimedia for Harry Potter and Attack on Titan, with validated local JPEG output. Fandom matching rejected ambiguous crossovers and Original Work. After installing the final Debug app, the existing Like A Memory entry automatically acquired a document-relative cover: one 60,514-byte JPEG. SQLite comparison with the pre-change snapshot retained its five chapters, chapter-two reading position and exact scroll fraction. This initially proved model/file integration; the later simulator session also confirmed the AO3 cover visually in both Continue Reading and the library row.
- Prepared-document checks passed paragraph normalization, scene breaks, word offsets and bookmark lookup. In an optimized isolated check, 120 reads of a 600-paragraph chapter took about 0.938 seconds with repeated preparation and 0.000089 seconds using the prepared list. This measures removed text preparation work, not scrolling FPS or a frame-time comparison.
- Existing pull-state checks passed interior fling, short pull, next/previous release, duplicate release, retreat and disabled cases. Git inspection confirms no changes to comic readers, shared pull logic or StatsUI.
- Final Debug and Release simulator builds passed on iPhone 17 Pro / iOS 26.4 (`build-final.log`, `release-final.log`). Existing warnings in unrelated files about missing direct SwiftData imports, and the skipped App Intents metadata step, remain. No new repository test suite was added; the scheme's empty TestAction is not presented as test coverage.

## Live simulator acceptance

The follow-up session used iPhone 17 Pro / iOS 26.4, displayed by Xcode 27.1 Device Hub (the replacement for its former Simulator app).

- Imported [Harry Potter and the Luck Potion](https://www.fanfiction.net/s/9591728/1/Harry-Potter-and-the-Luck-Potion) by Spiny Norman through the phone's FFNet browser session. All three chapters were committed, each marked complete with a readable local text file (1,418 / 1,858 / 531 bytes), and the local import job completed 3/3 with zero failures. Chapters two and three opened in the native reader. No companion backend was running or needed.
- Reimporting the same story after the mobile breadcrumb repair retained chapter three as the current chapter and its saved position. The fandom now reads Harry Potter. The initial live run exposed the missing mobile fandom and request-insensitive cover cooldown; both were repaired.
- The AO3 source-work cover appears in both the Continue Reading card and library row. The live FFNet story also acquired a 34,461-byte document-relative cover after the fandom repair. Both images were visibly confirmed in library rows and Continue Reading cards in the final installed app.
- CUA's instantaneous drags moved reader content but could not model a held edge pull. Its began/ended events had the same timestamp. An experimental monitor change was reverted. With the user's explicit approval, a temporary XCUITest project outside the repository ran paced gestures against the unchanged production pull monitor: a short boundary pull stayed in chapter two; a held, slow pull advanced to chapter three. The final compiled harness explicitly selected chapter two, including the check that it did not skip onward to chapter four. FinalAcceptance.xcresult contains the final held-pull check (15.2 seconds) and the scroll/reset/resume check (20.5 seconds): two tests, zero failures. No end-of-chapter page was added.
- The screenshot exposed a chapter-start offset hiding first lines behind the toolbar. The zero-anchor repair resets to the physical content top, including the phone safe-area inset, and avoids asking SwiftUI to align paragraph zero above its heading. Compatible saved pixel positions still take precedence. The final paced scroll/resume check passed: Start chapter over returned to 0%, the full heading and first paragraph were below the toolbar, an interior drag reached 7% without changing chapters, and exiting/reopening restored 7%. Start/reset and resumed screenshots are retained in FinalAcceptance.xcresult; the reset screenshot was also inspected visually.
- Final Debug test build and Release simulator build passed with Xcode 27.1. The Release app was installed after the checks. These are functional simulator checks, not a measured physical-device frame-rate result.
- The temporary harness initially reused an older installed runner; that exploratory run failed its chapter precondition and another selected zero tests. Neither is counted as acceptance. The rebuilt runner was explicitly installed before the final scroll check; the final combined acceptance run executed both tests with zero failures.

Evidence lives in /tmp/astral-fanfic-live-checks (live-story-results.json, parser-results.log, thumbnail-results.log, build logs and XCUITest result bundles). Initial model/Documents snapshots and fixture harnesses remain in /tmp/astral-fanfic-repairs. No repository test suite was added.
