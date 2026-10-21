# Astral rebuild: implementation and verification

21 October 2026. Implements the [app review](2026-10-21-app-review-and-rebuild-plan.md) and [reader/UI plan](2026-10-21-reader-interaction-and-ui-plan.md), with the user's correction: **keep pull-to-next-chapter**.

This is an implementation and verification record, not a released version. Existing project, reader and AO3 changes were preserved. No permanent hosted backend was started or migrated.

Follow-up: [phone sources and adjustable comic storage](2026-10-21-phone-sources-and-storage.md) supersedes the source and storage boundaries below. FFNet now has a device importer; excluded providers have not received complete live acceptance.

## Implemented

### Protect and manage the local collection

- Startup no longer deletes a database after an open error. It presents recovery with retry and verified-backup import.
- Settings exports a versioned backup containing a consistent SQLite snapshot, Documents content, bookmarks/models, and reading preferences. SHA-256 manifests and SQLite integrity are checked before a restore is staged.
- Restore runs before opening SwiftData on the next launch. It retains the replaced database/media as a recovery copy and rolls back file installation errors. These are same-schema Astral backups, not a cross-platform JSON interchange format or a guarantee of compatibility with future schema versions.
- Storage separates removal of saved copies from deleting a story. It explains that source/original files are needed again, retains metadata/progress, and journals the file move before database commit for interruption recovery.
- Permanent story deletion commits its model changes/tombstone before removing content. Save failures retain files. Companion sync excludes tombstones; acknowledged remote deletions remain excluded.
- No SwiftData entity schema was changed in this implementation. Source provenance, per-chapter positions and AO3 source chapter mappings use backed-up, namespaced metadata in preferences.

### Reading

- User correction: the unrequested end-of-chapter panels and paged transition pages have been removed from comics and fanfic. Pull remains at the actual content boundary; LTR/RTL comic pulls use source order. Named chapter/completion actions remain in More. The original panel verification below is historical, not the current interaction contract.

- Shared edge-pull logic uses the owning scroll view's adjusted bounds, not `UIScreen` coordinates. Start at the edge, exceed 120pt, then release. Retreat, cancel, duplicate release, auto-scroll, zoom and in-flight transitions cannot trigger another chapter change.
- Fanfic keeps vertical pulling and explicit chapter buttons; incidental horizontal swipes no longer navigate.
- Both readers load a candidate chapter before replacing the current one. A failure leaves current content available with retry/back actions.
- Controls are initially visible. Back/title/More and Chapters/position/settings replace crowded toolbars. Settings are scrollable sheets with Done and Reset. VoiceOver keeps controls available. Passage long-press and comic single/double-tap zoom have distinct handling.
- Reader foreground content respects safe areas; page/prose geometry does not move when chrome is shown. Backgrounds remain edge-to-edge.
- Comic RTL keeps source page IDs. Skip-page settings retain at least one page. Page count, bookmarks and position use the same logical page space.
- Fanfic progress comes from scroll offsets rather than paragraph appearance. Position metadata records chapter UUID, paragraph, viewport offset and typography/width signature. Layout/teardown offsets are excluded from genuine reading updates.
- Story completion is explicit. Opening the last chapter does not mark a work finished. Chapter position and finished status are separate.
- Auto-scroll pauses on sheets, chapter changes, backgrounding and boundaries. It starts explicitly from More. Zoom clamps its offsets and suppresses parent scrolling while magnified.
- Bookmark deletion offers Undo; chapter/passage bookmark entry passes an explicit initial anchor to the reader.

### Library, Add, Activity and sources

- Four visible primary destinations replace the hidden drawer. Comics/fanfic keep separate navigation/filter/browser state; launch opens the remembered content type.
- Search/filter controls appear in Library. Favourites search works. All filter fields persist together, including direction/category/word bounds/characters/relationships/ratings.
- Fanfic search includes authors, free tags and warnings. Source rating labels are retained and normalized when filtering, including Not rated. Empty results offer clear-search/filter actions.
- Fanfic rows are compact; detail places Read/Resume and rating/warnings ahead of expandable metadata. Metadata tags wrap and source engagement uses its source names. Continue Reading opens a reader directly.
- AO3 imports/updates create persistent Activity entries, support cancellation, keep the browser context and offer Read now/View in library. Source chapter IDs, where supplied by AO3, preserve identity through reordering. Removed source chapters remain saved locally. Legacy imports bootstrap their identity mapping on the first updated import; edit/reorder behavior still needs the full fixture matrix below.
- Text files can be imported locally. Comic image folders can be imported locally, with optional chapter subfolders, natural filename ordering, validation, cancellation, storage checks and transactional model commit. Comic copying runs outside the main actor.
- MangaDex has a device API adapter for English chapter metadata and chapter pages. Alternate releases are labeled by group. Acquisition is rate-spaced and surfaces rate limits. It does not use AO3/browser cookies or the Astral API.
- MangaDex request UUIDs are canonicalized to lowercase: live verification found uppercase UUID URLs returned 404 while lowercase URLs returned 200. Reader More now offers a named single-chapter offline save; saving one chapter does not mark the entire series downloaded. Chapter zero correctly offers Continue after reading and is not labeled Last Read before it is opened. Library cards show a source chapter label or available chapter count, rather than dividing the source chapter number by the release count.
- Comic library/detail covers use the existing bounded disk cache. Cache keys include the resolved source URL and use a filesystem-safe digest; writes are atomic and HTTP failures are not cached as images. This is an evictable cover cache, not preservation of source artwork in a library backup.
- The initial rebuild left FFNet and other legacy comic sources companion-dependent. The [phone-source follow-up](2026-10-21-phone-sources-and-storage.md) replaces that boundary and records the current verification limits.
- Companion configuration is optional and has no implicit OCI, localhost or fixed LAN address. Legacy jobs synchronize only when configured. Activity distinguishes opening, cancelling, retrying and dismissing history; dismissed remote history stays dismissed.
- Foreground downloads appear in Activity. They bound page requests, validate HTTP/image/counts, accept supported image formats, enforce storage limits and write a new generation before committing. Old copies survive replacement/save failure. Interrupted foreground jobs are marked actionable failures at launch. The UI does not claim automatic background resumption.

### Presentation and diagnostics

- Shared typography uses semantic styles. Secondary text was brightened. Reduced Motion disables app animation transactions. Closed/inactive navigation surfaces are excluded from accessibility.
- Stats lives under Settings as reading history, with All/Comics/Fanfic scope. Words/pages are labeled estimates; chapters are labeled opens. Comic tag dictionaries decode correctly.
- Shake diagnostics is DEBUG-only, and network logging omits response bodies.
- No decorative status dots were added.

## Verification record

- Pull correction: Debug simulator build passed (`/tmp/astral-pull-correction/build.log`), installed and launched. Source inspection confirms there are no inserted end sections, chapter footers or sentinel pages in either reader. The isolated pull-state check passed interior fling, short pull, next/previous, duplicate release, retreat and disabled cases. Simulator computer-use scrolling did not generate usable content movement, so this correction does not claim new tactile pull/release or RTL gesture proof. Existing source pages, guarded chapter loading and named chapter controls remain.

- Final Debug and Release simulator builds passed on the iPhone 17 Pro / iOS 26.4 destination, including the live-import corrections and single-chapter save. A generic-simulator Release build also passed earlier in the implementation. The final Debug app was installed and launched successfully. Build logs are `/tmp/astral-rebuild-build.log`, `/tmp/astral-rebuild-release.log` and `/tmp/astral-rebuild-release-final.log`.
- `git diff --check` passed. The only warning in the final build logs is Xcode skipping App Intents metadata extraction because this app has no AppIntents framework dependency.
- Before implementation, the simulator SQLite database and Documents were copied to `/tmp/astral-rebuild-20261021`; the initial working-tree patch was also retained there.
- Backup export was exercised in the simulator and produced a Files destination picker. Independent inspection found matching hashes, SQLite integrity `ok`, the existing five-chapter AO3 work, and the three-chapter comic fixture.
- An isolated harness using the backup implementation with temporary filesystem roots passed committed-WAL snapshot, file hash/integrity checks, media/preferences restore, retention of the previous library and rejection of modified content without changing the live harness collection. This caught and fixed relative-path alias and WAL-mode portability issues.
- An isolated check of the production pull state passed interior fling, short pull, threshold/release, previous/next, duplicate release, retreat and disabled-state cases. This proves state logic, not physical touch feel.
- Simulator navigation and fanfic viewport progress were exercised. Runtime inspection exposed a teardown-offset overwrite; tracking was changed to retain genuine scrolling and exclude teardown/layout events. The final check read to 13%, exited, reopened and retained 13%. A passage long-press opened only the bookmark sheet; cancelling retained the position and controls.
- AO3 was reimported through the phone browser. The browser retained its page and displayed Read now / View in library, while Activity displayed the completed local import with Open story. Database inspection confirmed one work with five chapters, all five AO3 chapter IDs mapped to the existing local chapter UUIDs, the saved chapter-two viewport retained, and no inferred story completion.
- The local comic fixture opened without a companion. Page selection reached source page 3, the now-removed end section did not automatically navigate, and explicit Next opened the one-page chapter 2.5. Switching to RTL preserved logical page 3 of 3. A blank view observed during a reading-mode change prompted an explicit mode-change restoration fix. The installed fix passed the follow-up: switching RTL to LTR retained the visible numbered source page 3 and Page 3 of 3.
- Contrast calculations for defined solid colors: secondary/elevated 5.69:1; body/dark 11.94:1; sepia body 9.92:1; paper body 12.31:1; gold/elevated 7.27:1. Materials, image overlays and every component have not been exhaustively measured.
- A live phone-side MangaDex import of The Ghostly Doctor completed with 446 English releases. Reader More saved its four-page chapter 0; Activity reported both import and download Ready to read. Database/file inspection confirmed one completed chapter download, four files totaling 7,599,096 bytes, and the series-level downloaded flag remained false. After app termination/relaunch, Continue opened the saved chapter, displayed its first page, and the chooser opened page 4 of 4. Detail correctly showed 1 of 446 chapters saved and Continue — Ch. 0. The installed reader selects local files before requesting source pages; this was a saved-file/relaunch check, not a radio-off network test. The earlier Solo Leveling example has no English chapters in its current feed.
- The manual comic corpus is opt-in (`--reader-fixtures`, DEBUG only), contains chapters 1, 2.5 and 10, a long image and a one-page chapter. Fixture behavior is not live-source scraping proof.
- No new repository test suites were added. The current Astral scheme has an empty TestAction; builds/manual/harness checks must not be presented as a full automated test run.

## Acceptance still requiring proof or further source work

1. Physical touch pull/release, diagonal motion, zoom/pan arbitration and LTR/RTL/skip-page resume across the full comic matrix; small phone/iPad/landscape, maximum Dynamic Type and full VoiceOver traversal. Computer-use drag events did not produce usable pan events, including in a system control; state-harness results must not be presented as tactile proof.
2. AO3 restricted login/challenges, long works, cancellation during each stage, chapter insertion/reorder/removal and source edits that invalidate passage anchors. Rich formatting/images/notes remain outside the current plain-text importer.
3. MangaDex alternate-volume/release ordering, provider failures, radio-off device use and large-collection performance beyond the verified 446-release metadata import / four-page save. The phone-source follow-up records FFNet acquisition and excluded provider acceptance separately.
4. OS-kill/disk-full/failing-file-move/save-error paths on an actual device, very large folder imports and backup selection/restore through the Files UI. Background transfers are deliberately not advertised as durable/resumable. Local file reimport currently creates another work rather than reconnecting a removed copy to its original metadata. Supported files are plain text and comic image folders; CBZ/EPUB import is not implemented.
5. Migration of any surviving OCI/Docker collection requires access to its database/media export. No current server data was available to migrate. Backups here are same-schema snapshots; a general portable metadata interchange and future explicit schema migrations remain future work.

Do not interpret these remaining runtime/source checks as completed merely because the application compiles. The two original reviews retain their historical observations; this file records the current implementation boundary.
