# Streamed comic reading, reader chrome and source browsers

23 October 2026. Follow-up to the reader reliability pass. The user reported small bugs across interactions, mostly in the comic reader while scrolling chapters whose pages are still loading, and found the browser basic.

## Comic reader (streamed chapters)

Reproduced on the simulator with The Ghostly Doctor (MangaDex, not saved) and a DEBUG-only `AstralSlowPages` delay of 0.9–3.5 s per page.

- **Jumps landed on blank or wrong pages.** `ScrollViewReader` placed unvisited pages from 2:3 size estimates, while real strips are several screens tall. A jump to page 9 landed in a black gap or past the end. Jumps now measure the target page after scrolling and correct until its top is at the viewport top.
- **Content moved while reading.** A page above the reading position finishing its load pushed everything below it. The reader now offsets the scroll by the height change of pages above the anchor, so the visible content stays still.
- **Page label lagged or flickered.** The label used the topmost visible page (often the tail of the previous page behind the top bar), and could pick the page that had just grown before the following pages reported their new positions. The current page is now the one under a line 40% down the screen, chosen only from a consistent set of frames.
- **Scrolling back reloaded everything.** Released images fell back to a 2:3 placeholder, and the page cache held about two decoded strips. Measured page sizes are now remembered for placeholders, the decoded cache is larger, and streamed page files are kept in a purgeable disk cache (see `wiki/concepts/offline-mode.md`). One quiet retry covers dropped connections; a failed page shows a Retry control.
- **Next chapter waited for a network round trip.** Near the end of a MangaDex chapter the reader fetches the next chapter's page list and its first pages. Pull or Next then opens immediately.
- **Exact resume was discarded after toggling controls.** The saved anchor's layout signature compared raw widths (402.00000000000006 vs 402.0), so a re-layout invalidated it. Comic and fanfic signatures now format sizes to one decimal, matching existing saved values.
- Previous/Next skip alternate releases of the chapter being read and prefer the same scanlation group.

## Reader chrome

- Status bar and home indicator hide with the controls in both readers. Readers opened from Continue Reading are now presented full screen (they were pushed, which kept the status bar and built the reader eagerly).
- Comic chapter titles are parsed for display: "Chapter 13" in the top bar; name, volume and group in the chapter sheet and detail rows. Stored titles are unchanged.
- The comic page menu (one item per page) is replaced by a page slider; the bottom bar has Previous/Next chapter buttons.
- Controls hide after a deliberate forward scroll in both readers; a tap shows them.
- Fanfic: taps on gaps between paragraphs and margins toggle the controls; prose fades out under the Dynamic Island and home indicator when the controls are hidden; the library row says "Chapter 3 of 5 · 41% of story" so it isn't confused with the in-chapter percentage.

## Source browsers

Both browsers share `BrowserChrome` (DesignSystem): source chips, a Safari-style address field showing the host, search on the selected source for non-address text, stop/reload, a loading line, pull to refresh, and a floating bottom bar. The bar's centre shows what the page allows: a hint, Add to library, Adding… with Cancel, or In library · Open/Read for stories already saved (MangaDex by title UUID, browser sources by series path, AO3/FFNet by canonical work URL). After an import a banner offers Read now / Open. Back/forward state follows in-page (SPA) navigation. Comic links to other sites show a "blocked" message; fan fiction author links open in Safari.

## Verification

Simulator iPhone 17 Pro, iOS 26.4, Debug build with slow pages and a cleared page cache:

- Jump to page 9 of a streamed chapter: lands on page 9; the page above finishing its load no longer moves the content; label correct. Scrolling up through unloaded pages keeps the label stable.
- Slider jump to page 7; held pull at the end opened chapter 14 from the prefetched page list; quick flings at the end did not change chapter.
- Exit/reopen mid-strip after toggling controls restored identical framing.
- L → R paged mode loaded streamed pages; reading mode restored to Webtoon afterwards.
- Fanfic: Continue Reading opened at the saved 7%; gap taps toggle controls; edge fades visible.
- Browsers: search "ghostly doctor" on MangaDex, Back/Forward through SPA history, In library · Open → comic detail; AO3 work URL → In library · Read → reader.
- AstralSmoke: 5 tests, 0 failures. Debug and Release simulator builds pass; `git diff --check` passes.

Not verified: physical device, radio-off behaviour, a live import through the new Add button (existing stories were used to avoid duplicates), ToonGod/Hentai20/nhentai pages (excluded from live testing earlier), VoiceOver traversal of the new chrome.
