# Polish pass 3: zoom, page turns, audit fixes

23 October 2026. Third pass after PR #70 (streamed reading, browsers) and PR #71 (story detail, Activity). Five read-only audits ran in parallel (comic paged reader, fan fiction reader and library, on-device scrapers, libraries and app shell, VoiceOver). Confirmed, contained findings were fixed; the rest are listed at the end with file references.

## New behaviour

- **Launch intro can be skipped.** Tapping the film ends it. Once it has finished, the fading film no longer catches the first tap meant for the library. VoiceOver reads "Astral, double-tap to skip".
- **Webtoon zoom covers the whole strip.** Pinch zooms around the fingers, the strip keeps scrolling while zoomed, a sideways drag pans, and double-tap toggles 2.2×. Before, each page zoomed on its own, the next page drew over it, and scrolling locked until you zoomed out. Paged modes keep per-page zoom. The zoom model is `ComicStripZoom`, which has unit tests.
- **Tap to turn pages in the paged modes.** A tap on the outer thirds moves toward the side tapped, so it follows both left-to-right and right-to-left order. The middle third still shows and hides the controls. Letterbox margins now take taps as well. A zoomed page, VoiceOver and taps past either end keep tap-to-toggle; a tap past the end shows the controls and their chapter buttons.

## Bugs fixed

### Comic reader
- A slow chapter load could replace a chapter opened in the meantime, so ch 10's pages appeared under ch 11's header and progress was saved against the wrong chapter. Stale loads are now dropped.
- Closing the reader while the next chapter was still loading recorded that unopened chapter as last read. The chapter switch is now a task that closing cancels.
- An unread "Ch. 5.5" opened at the page reached in Ch. 5. The old single last-page field is now only used for stories with no per-chapter positions.
- "Return to page N" carried over into the next chapter. Scroll jumps still in flight are now cancelled on chapter change and on close.
- "Bookmark current page" silently removed an existing bookmark. When it will remove one, the item now reads "Remove chapter bookmark".
- A paged page left zoomed came back zoomed while the reader thought nothing was.
- The pull hint offered "Release for next chapter" on the last chapter (and previous on the first), where releasing did nothing. This is fixed in both readers.

### Fan fiction
- Plain-text imports with Windows line endings, or one paragraph per line, became a single block laid out as one `Text`. They now split into paragraphs, which also fixes bookmarks and restore landing on paragraph 0. Unit tests cover this.
- The chapter row's bookmark action counted passage bookmarks, so "Remove bookmark" could delete a highlighted passage. It now acts on the chapter bookmark only.

### Libraries
- A reader opened from Continue Reading closed itself on "Mark finished", because the card that presented it left the strip. Both libraries now present it themselves (this was introduced in pass 2).
- Hiding search with the magnifier kept filtering the library with no visible search text. Closing search now clears it.
- The bookmark undo banner stayed over every tab until dismissed. It now leaves after 6 seconds.
- Title sort was case-sensitive and not number-aware. It now uses `localizedStandardCompare`.
- Comic and fan fiction detail saved SwiftData on every appearance. They now save only when the chapter count changed.

### Scrapers and saving
- A MangaDex import could crash if a chapter was added or removed while the feed was paged, which repeats a release. Duplicates are now dropped.
- MangaDex sends an empty description as `[]`. Decoding now tolerates it instead of failing the import.
- "Save all" stopped silently and reported "completed" when a page load was cancelled by a redirect (−999). Since pass 2, any `URLError.cancelled` had counted as the user cancelling. Now only the task's own cancellation stops a batch; anything else marks that chapter failed and the batch continues.
- Local comics with `.avif` pages were imported but then refused to open, because the reader's page list ignored `.avif`.
- AO3's "details could not be read" error told the user to open an FFNet page.

### VoiceOver
- Comic pages are read as "Page 3 of 12", and Retry says which page.
- Adjusting the page scrubber with VoiceOver now moves the reader. Before, it changed the number only.
- Reading-mode buttons are named ("Left to right") and marked selected. The brightness slider is "Dim pages". The Force Landscape switch has a name.
- The library favourite button is named and marked selected.
- The browser address field is no longer read twice when it isn't focused.

## Verification

iPhone 17 Pro simulator, iOS 26.4, Debug build:

- **Intro:** a tap mid-film skipped it, and the next tap opened Activity.
- **Webtoon zoom** (The Ghostly Doctor ch 14): pinch in, scroll down while zoomed, pan left, pinch back to fit.
- **Tap zones:**
  - L→R: right third → page 3, left third → page 2 (the tap landed on the black margin).
  - R→L: physical left third → page 3, as expected.
  - Middle third: hides the controls.
- **Continue Reading:** on the sample comic, the reader stayed open after Mark finished. The change was reverted afterwards.
- **Cancel:** the pass-2 cancel test was re-run after narrowing what counts as a cancel. Save next 5, then Cancel during the second chapter: two chapters saved, three returned to unsaved with no error, and the job reads cancelled · 2 of 5.
- **Tests:**
  - AstralSmoke 6/6, including the new `testTapSkipsIntro`. The launch tests now find the intro as any element type, because it is tappable.
  - ComicFeature 20, including 6 new `ComicStripZoom` tests.
  - FanficFeature 11, including 4 new paragraph-splitting tests.
  - Core 30 and DesignSystem 10.
  - The Core test target hadn't compiled, because `JobStatus` wasn't `CaseIterable`. It is now.

Not verified here:
- Double-tap zoom: the simulator tool can't send a quick enough double tap.
- VoiceOver on a device.
- The stale-load race and close-during-switch.
- Held pull-to-next while zoomed.
- The scraper fixes: no live imports ran this pass.
- Anything on a physical device.

## Found, not fixed

These need a decision or are larger than this pass:

- **Force Landscape does nothing.** Info.plist allows portrait only and the target is iPhone-only, so the request is rejected (`ComicReaderView` settings). Either support landscape in the reader or remove the toggle.
- **Webtoon zoom edges.** At 2× and above, roughly the top and bottom quarter-screen of a chapter can't be reached while zoomed. The page label uses the unzoomed reading line.
- **Backup and restore hash files on the main thread,** and a pending restore re-hashes at launch. With a multi-GB library that could exceed the launch time limit and repeat on every launch (`LibraryBackupService.swift`, `AstralApp.swift`).
- **Re-importing a comic from before the rebuild creates a duplicate**, because matching relies on keys only the companion writes (`DeviceComicService`, `MangaDexDeviceService`).
- **Orphaned files are never cleaned up** after an interrupted import or save, and `AstralBeforeRestore-*` copies are kept forever (`OrphanCleanupService`).
- **The hidden page loader** has no domain allowlist and throws on concurrent loads from the same source (`DeviceSourcePageLoader`).
- **AO3:**
  - Image-only chapters (fanart, podfic embeds) fail the whole import.
  - Collection URLs are rejected.
  - `parseInt` stops at "1,234".
- **FFNet:** the chapter count is read from the whole page, so a one-shot whose text says "Chapter 1 of 3" goes looking for chapter 2.
- **MangaDex:**
  - A chapter's stored page count goes stale after an uploader edit, which blocks saving.
  - API calls don't retry 5xx responses.
- **Heavy main-thread work:** AO3/FFNet import parsing and re-encoding, and per-page storage queries during comic saves.
- **Fan fiction reader:**
  - A chapter that fits on one screen reads 0%, so the story never reaches 100%.
  - `<br>` line breaks are flattened.
  - The System font ignores Dynamic Type.
- **Libraries:**
  - Value-based navigation instead of inline `NavigationLink` in the grid and list.
  - The Completion filter hides comics with unknown status.
  - The tag filter matches raw JSON.
  - Sort counts as a filter for the empty state.
  - Filters are recomputed several times per render.
  - Stats and Storage are slow with large libraries.
- **Activity:** companion jobs stay "running" forever once the companion is off.
- **VoiceOver:**
  - No announcements for toasts or chapter changes.
  - The current-chapter marker in chapter sheets is colour only.
  - Fixed heights in the browser chrome and reader bottom bar clip at the largest text sizes.
- **Dead code:** the Scrapes views, `ComicSearchView`, the sidebars, `TabBarView` and `FanficLibraryViewModel`.
