# Story detail and Activity polish

23 October 2026. Second pass after the streamed-reading work (PR #70), covering the screens between the library and the readers.

## Bugs fixed

- **Comic detail swipe actions never worked.** `.swipeActions` only works on `List` rows; the chapter and bookmark rows are in a `LazyVStack`. Bookmarking is now a long-press menu (matching fan fiction) and bookmarks have a delete button.
- **Comic detail re-sorted every chapter repeatedly.** A scroll-offset preference updated state on every scroll frame although nothing read it, and the ordered chapter list (446 chapters for The Ghostly Doctor) was recomputed for each row's bookmark check. Ordering and the bookmark index are now computed once per update.
- **The download button saved every chapter with no feedback.** It is now a menu: Save next 5 / next 10 (from the chapter being read, in reading order) or all unsaved, with "Saving 2 of 5… Cancel" in the chapter toolbar. Long-press a chapter to save just that one.
- **Cancelling a save marked the chapter "failed".** URLSession reports cancellation as `URLError.cancelled`; the service now treats it as cancellation, leaves the chapter unsaved without an error, and stops the batch.
- **Fan fiction word counts read "0K / 1K words"** (integer division). Rows now show "1,250 words · 5 min".
- **AO3's "Creator Chose Not To Use Archive Warnings" was shown as a warning.** Real warnings stay highlighted; AO3's "no warnings" values are shown as information.
- **Raw source keys** (MANGADEX-DEVICE, FFNET) in Activity and library rows. One `SourceLabel` helper in Core now names sources everywhere, including both browsers.
- The MangaDex Add bar could say "Loading the series…" although MangaDex imports don't depend on page loading.

## Polish

- Comic detail: cover header with source and status, "Continue — Ch. 14, page 2", compact one-line rows with name, group and page count, "Reading" marker on the current chapter, jump-to-current, oldest/newest toggle, Mark as finished in the ••• menu.
- Fan fiction detail: cover/author/rating/status header, "Continue — Ch. 3 · 7%" from the saved position, saved-state icons only when some chapters are unsaved.
- Activity titles come from the library first, so folder imports show the story name rather than the folder name.
- Activity: sections for In progress / Needs attention / Done; titles from the library; summaries such as "Imported from MangaDex · 2 chapters" or "Saving stopped · 3 of 5 saved"; relative dates; swipe to remove; Clear with confirmation. Repeated failures at the same source collapse to the latest, and failures a later run resolved are hidden.
- Undo banner uses the app's gold accent.
- Library: "Ch. 14 of 446" on comic cards (the ring now starts at 12 o'clock); "FanFiction.net" in fan fiction rows.

## Verification

iPhone 17 Pro simulator, iOS 26.4, Debug:

- Jump-to-current centres Ch. 14; long-press → Bookmark chapter shows the bookmark icon; the Bookmarks tab delete button removes it with an Undo banner (comics and fan fiction).
- Cancel with the fix in place: Save next 5 from Ch. 14 saved 17–19, Cancel left 20–21 unsaved with no error, and the job reads cancelled · 3 of 5 with no failures. (A cancel before the fix had left a chapter marked failed; it re-saved normally.)
- Live MangaDex import of "Shiga wa Mitame de Sonshiteru" (2 chapters): Add → banner → In library · Open → detail → streamed Chapter 1. Saving its chapters was correctly refused by the 2-comic offline limit; the message appears in an alert and in Activity.
- Activity, fan fiction detail and library rows checked visually.
- AstralSmoke 5/5; Debug and Release simulator builds; `git diff --check`.

The test title remains in the simulator library. Not verified: physical device, VoiceOver traversal of the new rows and menus.
