# Fan fiction formatting, source links and comic covers

23 October 2026. Follow-up to PR #72, from testing on the phone.

## Fan fiction text (focus on AO3)

A scan of the AO3 stories in the simulator library, plus checks in the reader, found these problems:

- **Italics and bold were dropped on import.** Thoughts, emphasis, newspaper headlines and quiz questions all read as plain text.
  - **Fix:** the AO3 and FFNet importers now wrap `em/i/cite` and `strong/b` in private-use marks (U+E000–U+E003) inside the saved plain text.
  - **Reader:** it turns the marks into italic and bold in the chosen reader font (`FanficTextMarks`).
  - **Elsewhere:** word counts, scene-break detection and bookmark snippets strip the marks.
  - **Old copies:** text saved without marks still reads as before.
- **Line breaks inside a paragraph were flattened.** Examples are a guest list and a herb inventory; there were seven such places across the AO3 stories in the library.
  - **Fix:** imported stories now keep single line breaks.
  - **Plain-text files** still join wrapped lines, because they are often hard-wrapped.
  - This takes effect without re-importing.
- **Centred text was left-aligned.** Centred paragraphs are now marked and centred in the reader.
- **List items** now get bullets.
- **Untitled chapters said it twice.** "Chapter 1 / Chapter 1" appeared in the reader heading, and "Ch. 1 Chapter 1" in the story's chapter list. The repeated title is now hidden; 50 of 91 AO3 chapters in the library were affected.
- **Spacing:** spaces just inside italic runs at the start or end of a line are trimmed, and authors' double spaces after full stops are collapsed.

Italics, bold, centring and bullets need **Update from AO3** (or FanFiction.net) on stories imported before this change. The line-break and heading fixes apply immediately.

## Source links

- **Story page:** the author and the source line ("AO3 ↗") in the story header are links. Before, there was only a small source chip inside Story details.
  - **Authors:** AO3 bylines open the author's page; pseuds open `/users/<user>/pseuds/<pseud>`.
  - **FanFiction.net authors:** these open a writer search, because the importer doesn't keep profile IDs.
- **Reader:** the ••• menu has **Story page** and **<author>'s page**.
- **Where links open:** in Add, not Safari, so the page can be updated from there. The browser now follows a requested page's host, so author and search pages open on the right source.

## Reader menus opened from Continue Reading

The fan fiction reader's ••• menu and its sheets (reading settings, chapters) closed immediately when the reader was opened from Continue Reading. This was a regression from PR #72, which moved that presentation into the library to fix "Mark finished".

- **Cause:** render logging showed that opening the menu rebuilt the reader (`@identity` changed) when it was presented from inside the tab's NavigationStack.
- **Fix:** Continue Reading now presents from the fan fiction tab root through `FanficNavigation.readerSelection`. The selection carries its chapters, so the cover doesn't run its own query.
- **Comics:** the comic Continue Reading menu worked in testing and keeps its library-level presentation. It now also carries its chapters instead of querying.

## Comic covers

The Hentai20 comic on the phone had no cover because the importer saved `…/undefined` as its cover URL.

- **Cause:** that theme marks its cover with `img.wp-post-image[itemprop=image]`, which the importer didn't check, and a missing value went through `new URL(String(undefined))`.
- **Fix:** the importer now reads that cover and treats a missing value as missing.
- **Updates:** an update that finds no cover keeps the saved one, and clears a stored `…/undefined`.
- **Existing comics:** they get their cover on their next check for new chapters.

## Verification

iPhone 17 Pro simulator, Debug:

- **Formatting:**
  - **Update from AO3** on a 50-chapter story saved 16 italic and 49 bold runs.
  - Chapter 3 shows italic thoughts, both whole lines and mid-paragraph.
  - The chapter list reads "Ch. 1" without a repeated title.
- **Links:**
  - Header links read "by orphan_account" and "AO3 ↗ · Teen And Up Audiences · Ongoing".
  - Tapping the author opened `/users/orphan_account` in Add.
  - Reader menu → **Story page** closed the reader and opened the work in Add, showing "In library · Read".
- **Continue Reading:**
  - Fan fiction: with the tab-root presentation, the ••• menu opens with the gold tint and shows the new links. **Mark finished** keeps the reader open (reverted afterwards).
  - Comics: the ••• menu opens.
  - Story page: the reader menu still works when opened from there.
- **FanFiction.net line breaks:** a scan found 13 blocks with line breaks in FFNet chapters. All are dialogue lines, none mid-sentence, so FFNet keeps them too.
- **Comic covers:** the Hentai20 series page markup has the cover as `img.wp-post-image[itemprop=image]`, and the image loads without a referrer. The importer itself wasn't run against Hentai20 in the simulator.
- **Tests:** FanficFeature 18, including 5 new formatting and mark-trimming tests. For AstralSmoke and the other packages, see the PR.
