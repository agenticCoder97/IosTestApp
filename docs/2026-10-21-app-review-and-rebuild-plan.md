# Astral: app review and rebuild plan

Reviewed 21 October 2026. Scope: comics, fanfiction, shared UI, local persistence, networking and the backend boundary. This is the original review and proposed plan. See [implementation and verification](2026-10-21-rebuild-implementation.md) for the subsequent changes and outstanding checks.

Follow-up: [reader interactions and UI integration plan](2026-10-21-reader-interaction-and-ui-plan.md) specifies the second-pass design. It retains deliberate pull-to-next-chapter alongside explicit chapter actions and defines gesture ownership, safe-area layout, visual hierarchy and implementation acceptance criteria.

## Recommendation

Build a personal, local-first reading app. The phone owns the library, saved content, reading position, bookmarks and preferences. Sources provide content; an Astral server must not be required to open or manage the library. Keep Docker as a development environment and optional bulk-import companion during transition. Do not choose a replacement cloud host until a concrete feature proves it needs one.

The strongest reusable parts are the Swift package boundaries, SwiftData entities, both reading surfaces, reader preferences, bookmark UI, source browser, and design tokens. Rework the data lifecycle and navigation underneath them. A wholesale rewrite would discard useful behavior and risk the existing collection without solving source access by itself.

OCI: the previous account inspection established Pay As You Go and no verified available promotional balance. It did not establish a precise credit-expiration date. The plan therefore assumes no dependable OCI service, independently of whether credits expired.

## Evidence and coverage

- **Live**: current iPhone 17 Pro / iOS 26.4 simulator build. Inspected populated fanfic library, filter sheet, favourites empty state, story metadata, reader, typography controls, passage bookmark sheet, statistics, sidebar/type switch, comics offline library, comics filter sheet, browser controls, favourites and scrape queue empty states.
- **Source**: screen/control inventory below, including populated comics detail and reader, job detail/retry, downloads, persistence, networking, models, shared statistics and backend tasks. Source findings are not claims that every interaction was executed.
- **Prior session evidence**: AO3 five-chapter import, reimport preserving identifiers/progress, reading chapters, relaunch persistence and missing-work failure were exercised before this review. Those are not new tests from this review.
- **Blocked/unverified live**: simulator contains no comics; the backend is unavailable. Docker CLI is installed but `docker info` fails because its daemon socket is absent. Populated comic reading/download/archive flows and active/failed server jobs consequently need a separate runtime pass. No server was started and no app data was deleted for this audit.
- Not yet verified: physical device, iPad, VoiceOver traversal, largest Dynamic Type, background transfer recovery, large collections, very long works, authenticated/locked works and each external comic source. No blanket “all functions passed” claim is warranted.
- Existing working-tree changes were preserved. This review adds documentation only.

## Screen and control review

Evidence: L = observed live this review; S = source-inspected. Prior AO3 testing is called out separately above.

| Surface | Functions and UI elements | Assessment and rebuild disposition | Evidence |
|---|---|---|---|
| Launch / landing | Animated gold/blue orbs, title/subtitle, Comics and Fan Fiction selection, reduced-motion branch | Several animation phases gate entry on every cold launch. Transparent half-screen tap zones lack explicit descriptive labels. Open the last-used library immediately; retain branding as optional first-run polish. | S |
| App shell | Content-type menu, search toggle, filter button, right drawer, navigation stack | Main destinations are hidden; global search/filter remain in Browse, Scrapes and Stats even though those screens do not consume them. Use visible primary navigation and context-specific controls. Preserve independent navigation state when switching content types. | L/S |
| Sidebars | Library, Favourites, Browse, Scrapes, Stats; tap outside dismiss | Closed drawer remains in accessibility tree in live captures; source offsets it but does not hide accessibility or disable interaction. Replace with standard navigation or explicitly hide inactive drawer content. | L/S |
| Comics library | Two-column covers, source icon, title, chapter count, heart, new-chapter badge, archive/restore status, progress; Continue Reading; update timestamp; refresh; retry banner; context menu | Local records are displayed, but every library/favourites entry triggers server synchronization. Empty library becomes a backend error. Make local content authoritative, distinguish empty/no matches/unavailable source, and give an Add action. Cache covers locally. | L empty / S populated |
| Comics search | Title/description/tags/authors/category matching; separate ranked search view exists | Active library uses substring matching over JSON; ranked `ComicSearchView` has no call site found. Consolidate one search implementation and typed metadata. | S |
| Comics favourites | Heart action, filtered collection, normal search/filter chrome | Search binding is `.constant("")`, so typing has no effect here. Filters still apply and may hide favourites without explaining why. | L/S |
| Comics filters | Last Read/Date Added/Title/Chapters; ascending; archived visibility; completion; tags; category; source; Reset/Done | Sort direction and category changes alone do not trigger persistence. Completion field exists locally but normal library upsert does not populate it. Preserve whole filter snapshot; show active chips and Clear Filters when empty. | L/S |
| Comics detail | Cover hero/collapsing title, description, author/tag links, metadata, read/resume, chapters/bookmarks tabs, download toggle, archive/restore, delete menu | Reading competes with large metadata region. Download icon silently removes all local pages once fully downloaded. Archive means server image recompression, not simply hiding a title. Separate Read, Download and Storage actions with explicit names and consequences. | S |
| Comics chapter rows | Chapter title/number, last-read marker, page count, scrape/download states, chapter selection, bookmark context action | Collapse internal scrape status into meaningful availability: saved, needs download, unavailable, failed. Distinguish current position from completed chapter. | S |
| Comics bookmarks | Chapter/page/note, open, delete; expandable bookmark section | Preserve core behavior; add stable chapter identity and undo for bookmark deletion. Check restore-at-page including skipped cover pages and decimal chapter numbers. | S |
| Comics reader | Webtoon, left-to-right, right-to-left; previous/next; overscroll chapter triggers; chapter list; page slider/menu; back; favourite; bookmark; settings; zoom/pan/double tap; loading/offline/retry | Keep capabilities. Validate gesture arbitration, visible escape route on error, resume position, zoom vs page turns and long-strip memory. Current progress truncates decimal chapter numbers and treats chapter number as completed count. | S |
| Comics reader settings | Reading mode, skip first N pages, brightness overlay, auto-scroll toggle/speed, force landscape | Keep useful settings but separate global defaults from per-title overrides. Label sliders/toggles, provide Reset, ensure auto-scroll stops on exit/background and rotation is reversible. | S |
| Comics browser | Source picker (MangaDex, ToonGod, Hentai20, NHentai), back/forward/reload, URL entry, lock/loading state, import icon, source-home, toast | Site browsing is on-device, import sends cookies/UA to server. Arbitrary URL field is constrained by selected-source allowlist; unsupported navigation can silently cancel. Make source selection/URL recognition consistent; explain disabled import. Shared browser should expose source capabilities. | L controls / S behavior |
| MangaDex match proposal | Cover/title suggestion, Use MangaDex / Keep original source | Preserve as optional later enhancement. Verify edition, language, chapter coverage and provenance before substitution; confidence is not content equivalence. | S |
| Comics Scrapes | Time chips, status groups, job rows, progress/current step, failures, retry, delete, pull refresh, five-second polling | Rename to Imports/Downloads. No server must be a clear unavailable state, not indistinguishable from no jobs. Local job deletion is undone by subsequent server upsert. Make dismiss-history and cancel-work distinct actions. | L empty / S populated |
| Job details (both types) | Job metadata, timestamps, errors, event log, Done | Keep actionable failure and retry near the item; put technical event logs under diagnostics. Empty log currently also covers fetch failure. | S |
| Fanfic library | Continue Reading, row thumbnail/placeholder, title/author, summary, fandom/rating chips, chapter count, source engagement, date, heart, progress; delete | AO3 already works locally. Rows are tall and information-dense; long tag chip clips horizontally. Use compact title/author/progress by default; secondary metadata belongs in detail. “Updated” should say whether it means local import or source publication. | L/S |
| Fanfic search/favourites | Title/fandom/characters/relationship/summary/rating search; favourites | Favourites ignores typed search. Search omits author and freeform tags, even though tags in detail initiate a search; some tag taps therefore yield no match. Search semantics should match every navigable metadata link. | L/S |
| Fanfic filters | Six sort modes and direction; fandom; completion; word limits; G/T/M/E; character; relationship; AO3/FFNet; Reset/Done | AO3 imported rating names do not equal G/T/M/E. Most filter fields are encoded but not watched for saving. Warning filter state exists without a corresponding implemented filtering path. Normalize ratings, persist atomically, validate min ≤ max, and show result count. | L/S |
| Fanfic detail | Title/author/source link, summary, rating/status, words/chapters, hits/kudos/comments/bookmarks, fandom/relationships/characters/warnings/free tags, dates, Continue, update/reimport, chapter/bookmark tabs, delete | Preserve metadata fidelity but collapse long tag lists; put Read near top. Two AO3 controls lead to reimport. Source kudos/bookmarks are relabeled Likes/Saves, easily confused with local favourites/bookmarks. Use source names and distinguish local actions. | L/S |
| Fanfic chapter/bookmark lists | Chapter selection/download state/word counts, chapter bookmark, passage/note, open/delete | Preserve. Use content-stable anchors for passages; number-only association cannot reliably survive author chapter insertion/reordering. | L/S |
| Fanfic reader | Plain-text paragraphs/scene breaks, horizontal chapter navigation, footer prev/next, overscroll affordance, hidden chrome, chapter chooser, back/favourite/settings, paragraph bookmark/note | Long press both toggles chrome and opens bookmark sheet; reproduced together. Scroll progress uses paragraph `onAppear` in a non-lazy VStack, not viewport position. Replace with actual visible anchor tracking. Provide discoverable chrome without conflicting with selection/bookmarks. | L/S |
| Fanfic typography | System/Open Sans/Georgia/Palatino/Courier/Avenir; font size; line height; paragraph gap; margins; dark/sepia/paper | Good reusable controls. Background buttons are unnamed in accessibility snapshot; settings icon says “Edit”. Add labels, selection values and text-size support. Preserve position when typography changes. | L/S |
| Passage bookmark sheet | Passage preview, note/title input, Cancel/Save | Keep; distinguish selection from whole-paragraph bookmarking. Ensure gesture can be invoked without also changing chrome. Did not save/delete personal bookmarks during review. | L/S |
| Fanfic browser | AO3/FFNet, standard navigation/URL/home, import, loading, toast/alert | AO3 imports within WKWebView and saves locally; FFNet remains backend dependent. Make that availability explicit. Preserve browser session across sections. Provide paste-link and later share-sheet entry. | S; prior AO3 live verification |
| AO3 importer/update | Canonical URL dedup, full-work extraction, chapter-count validation, atomic file staging, model rollback, login/challenge/rate-limit/errors | Retain as foundation. Current format intentionally loses rich text/images/notes. Update matches chapters by ordinal and preserves numeric offsets; insertion/editing can move bookmarks. Add stable source chapter identifiers and content versions before promising robust update semantics. | S; prior live verification |
| Fanfic Scrapes | Same queue/log/retry controls as comics; server thumbnail allocation | AO3 does not create jobs here, so instructions are misleading. Replace with shared local import history; remove server/random-thumbnail dependency from new local imports. FFNet state must explicitly say companion needed until migrated. | L/S |
| Statistics (both destinations) | Words/pages/chapters, streaks, reading time/average; heatmap/day sheet; weekly activity; backlog/almost done/completions; source/fandom/tag/rating breakdown; bookmark analytics/highlights; timeline | Both destinations show the same combined data. Make one clearly labeled Stats surface with All/Comics/Fanfic scope. Current measures estimate reading from chapter position; do not label estimates as measured pages/words read. Hide irrelevant zero cards, reduce visual density. | L upper / S entire surface |
| Statistics day sheet | Selected date, session list, titles, chapter counts, durations, Done | Keep only if useful after metrics become correct. Heatmap buttons need date/value labels. A session records chapters opened, not necessarily read. | S |
| Debug console | Shake entry, All/Network/Errors/Warnings/Info filters, log rows, Clear/Done | Comment claims DEBUG-only but wrapper has no compile-time DEBUG guard. Log list snapshots on appear. Make developer-only or explicit diagnostics; redact content/URLs where appropriate. | S |
| Shared feedback | Empty states, banners, toasts, progress bars, status icons, destructive alert, search bar, filter chips | Keep reusable primitives; standardize wording, accessibility labels, retry/clear actions, loading/cancellation/error behavior. Use activity indicators only for real work. | L/S |
| Missing user surfaces | Settings, storage manager, backup/export/restore, file import, source/session management | Add these before advanced analytics or server migration. No general user-facing implementations found. A local-only library must be recoverable and manageable. | S |

## Prioritized findings

### P0 — protect the collection before structural changes

1. **Database failure destroys the store.** `AstralApp.swift:42` catches any container creation error and removes the SQLite database and sidecars. This is not limited to a verified incompatible schema. Replace with explicit versioned migration, recoverable startup error and backup/recovery. Never automatically erase a user's library.
2. **No user-facing portable recovery path.** SwiftData plus Documents files is the collection, but there is no app export/restore. Preserve DB and media together before migrations; implement a versioned export manifest with content files, bookmarks, progress and preferences. An OS backup alone is not a user-controlled portability workflow.

### P1 — correctness and ability to read without infrastructure

3. **Comics require a backend for fresh content and metadata.** `ComicLibraryViewModel.fetchComics`, detail sync, browser import, reader fallback and download services all call Astral endpoints. Convert to a local repository and source adapters; preserve legacy import bridge until data is migrated.
4. **Read position is mistaken for completion.** Both readers divide chapter number by total count. Opening the final chapter can mark completion; non-contiguous and decimal comic numbering breaks this further. Store chapter ID/order and viewport position separately from completion. Stats must consume real completion/session events.
5. **Fanfic scroll tracking is not viewport tracking.** `FanficReaderView.swift:125` uses paragraph `onAppear` inside VStack. Re-rendering/eager appearance can overwrite progress. Validate with start/middle/end, typography changes and relaunch; use visible anchor/offset instead.
6. **Destructive download toggle.** `ComicDetailView.handleDownloadTap` removes all saved pages when all are present; FFNet detail follows the same broad pattern. Expose explicit Remove Downloads with consequences. For locally imported sole copies, removal must not masquerade as a reversible cache action.
7. **Download lifecycle is incomplete.** Detail calls foreground `downloadAllChapters`; background method has no UI call site. Background task routing is only in memory, callbacks are a singleton slot, and launch cleanup removes staging/reset states. Do not claim resumable background operation until a durable manifest, session reconciliation, cancellation and validation exist.
8. **Downloaded bytes and database state can diverge.** Comic replacement removes old directory before final model commit; save failure removes new files without preserving old version. Page download task group is unbounded across a chapter. Add bounded concurrency, expected-page validation and rollback-safe replacement. JPEG/PNG validation currently rejects WebP, while archive task generates WebP.
9. **Archive/restore can remain stuck.** Local status is set optimistically and network failure swallowed (`ComicDetailView:620`, library equivalents). “Restore Full Quality” depends on re-scraping the external source; it cannot guarantee recovery. Remove this server-space feature from the default phone workflow or make it an explicit optional compression operation with originals preserved.
10. **Reader gesture collision.** Paragraph long press is 0.5s and global chrome long press 0.25s. Both can fire. Give chrome and passage selection distinct interactions plus accessible alternatives.
11. **Rating filters exclude valid imported works.** `AO3Import.js:87` stores full AO3 rating text; `FanficRating` defines G/T/M/E; library compares exact strings. Normalize at model boundary while retaining original source label. Include unknown/not-rated handling.
12. **Delete/sync race risks resurrection.** Remote-delete failure queues a pending deletion, but normal comics library upsert does not exclude those IDs. Keep durable tombstones until acknowledged, or eliminate remote authority. File/model deletions currently swallow save failures as well.

### P2 — coherent everyday use

13. Persist the entire filter snapshot. Fanfic only observes sort/fandom/completion/source; comics omits category and sort direction. Changes to other fields only persist incidentally when a watched field changes.
14. Fix search in favourites; scope toolbar controls; include authors/free tags and typed metadata search; show No Matches with Clear Filters rather than No Stories.
15. Rename Scrapes to Imports, include AO3 local operations, and distinguish queue-history deletion from canceling work. Server errors must not appear as empty queues/logs. First-page-only jobs (100) and comics (200) also need pagination if the bridge remains.
16. Accessibility pass: drawer hidden state, explicit icon labels, background names/selection, heatmap date/value, launch labels, Dynamic Type and contrast. Fixed font sizes and dim gray metadata need live device validation; screenshots alone are not a contrast audit.
17. Make reader entry/resume immediate, metadata secondary, and navigation reachable with one hand. Preserve useful comic modes and fanfic typography; consolidate duplicate UI, not distinct reading behavior.
18. Correct statistics semantics. `StatsData` computes pages/chapters from last chapter number and words from estimated progress. Comic tags are stored as dictionaries while stats decode `[String]`, losing comic tag counts. Session timing/background return and chapter counts also need validation. Shared stats should identify its scope.
19. Normalize import provenance, chapter identity and bookmark anchors; cache covers locally; preserve formatting as a later reader-format migration rather than silently replacing plain text with arbitrary HTML.
20. Make diagnostics explicitly development-only or opt-in. Remove dead/duplicated implementations after route migration, including unused ranked comic search and obsolete fanfic library VM.

## Backend decision by capability

| Capability | Default home | Server decision |
|---|---|---|
| Library metadata, search, filters, favourites, bookmarks, progress, preferences, stats | Phone database | No server required |
| Saved chapters/pages/covers | Phone files with manifest | No server required; storage limits and backup essential |
| AO3 browse/import/update | Phone browser session and importer | Already implemented foundation; harden update fidelity |
| Comic browsing | Phone browser | Already on device; adapter feasibility still source-specific |
| MangaDex metadata/chapter acquisition | Candidate direct phone adapter | Existing Python adapter is reusable logic, not proof of Swift/device reliability; prototype first |
| Other comic sources / FFNet | Capability-gated source adapters | Device feasibility must be measured. Offer file import/optional companion if direct acquisition is unreliable; do not promise Cloudflare immunity |
| Large imports / expensive conversion | Optional Mac/Docker companion | Useful when requested; phone should keep working after companion stops |
| Backup and device transfer | Export/import first | Optional personal cloud storage later; not a reason to host an Astral API now |
| Continuous unattended source monitoring | Deferred | A credible reason for an always-on service, if actually wanted later |
| Public catalog/accounts/social features | Out of initial scope | No current single-user need |

## Proposed product structure

Four primary destinations: **Library · Add · Activity · Settings**.

- Library: Comics/Fanfic scope with independent state, Continue Reading, compact collection; Favourites/Saved/Unread as filters. Search and filter only here.
- Add: paste a link, browse a supported source, import a file. Supported behavior is explicit for each source; preserve browser session. File import is a planned feature, not current functionality.
- Activity: local import/download jobs with progress, cancellation, actionable failure and retry. Reading history/stats available as a secondary view, not duplicated under both content types.
- Settings: reading defaults, appearance/accessibility, storage usage/removal, export/restore, source sessions, optional companion connection and diagnostics.
- Detail: title/author and Read first; availability, chapters, bookmarks next; expandable metadata. Source engagement is clearly separate from local actions.
- Reader: minimal visible entry controls, one discoverable chrome gesture, independent selection/bookmark gesture, deliberate pull and explicit chapter navigation. Remember content position across preference changes.

This is a proposed information architecture, not a frozen visual design. Retain the dark/gold identity if desired, but use semantic colors, readable secondary text and less card nesting. No decorative status dots.

## Rebuild sequence and acceptance gates

| Phase | Work | Gate before proceeding |
|---|---|---|
| 0 — preservation and baseline | Snapshot existing store/media; remove erase-on-open-failure; document schema; export/restore; establish representative corpus and runtime matrix | Existing collection survives upgrade, failed migration shows recovery, restored export preserves IDs/files/bookmarks/position |
| 1 — local core | Local repository, stable source/work/chapter IDs, versioned content manifest, transaction-safe writes/deletion, durable import/download job model; isolate optional legacy API | Both libraries open and are manageable with no server; errors leave previous content intact; no queued remote action can resurrect deleted content |
| 2 — AO3 complete vertical slice | Fix ratings/search/filter persistence; stable update/bookmark behavior; fix viewport tracking/gesture conflict/completion; unified local activity | Import → find → read → bookmark → quit → resume → update succeeds without Astral API; cancellation and invalid work retain saved copy |
| 3 — shell and everyday UI | New navigation, compact library, focused detail, source-aware Add, actionable Activity, storage/settings | Every visible control has an effect in its context; one-handed flows; empty/no-results/error distinct; VoiceOver and large text pass |
| 4 — comics local vertical slice | Direct source prototype (start with existing API-oriented MangaDex adapter), portable comic file import, page manifests, bounded downloads, cover caching, reader integration | Real comic import and offline reading in all three modes; decimal chapters, zoom, skip pages and resume correct; no backend needed after import |
| 5 — FFNet and remaining sources | Feasibility spike per source; direct session acquisition where reliable; optional Docker bridge/file fallback; source-specific rate-limit/errors | Each advertised source has demonstrated device import/update or an explicit supported fallback; no misleading working badge |
| 6 — polish and optional extras | Accurate scoped stats, accessibility/performance, diagnostics, optional personal sync or companion improvements | Long-work/large-library/device/lifecycle checks pass; performance and storage measured; server hosting introduced only for an accepted unmet requirement |

Phases overlap where safe: data safety first; AO3 remains the fastest useful vertical slice; UI refinements can run alongside source feasibility. Do not postpone all reader fixes until after a visual reskin. Do not delete the Python backend until all needed legacy data and unsupported-source behavior have a replacement.

## Docker and migration workstream

`backend/docker-compose.local.yml` already defines API, ARQ worker, PostgreSQL, Redis, media volume and optional admin tools. It is usable as a starting configuration; runtime health was not verified because Docker is stopped.

When used, start only necessary services, inspect volumes before migrations, verify API/worker/media separately, and keep local data intact. Current local ports bind broadly and credentials are development defaults. The inspected FastAPI routes have database dependencies but no application-level authentication; do not deploy this unchanged to a public replacement host. A private companion should have explicit pairing/authentication and a configured endpoint, not a hardcoded LAN IP.

For existing server content: export metadata plus all media with stable IDs and source URLs; record missing files; import transactionally on phone; verify counts and sample chapters/bookmarks/progress; retain original backup until validated. The current LocalComic model lacks a general canonical source URL field, so migration must recover source identity from backend data rather than inferring it from titles.

If an always-on backend is later justified, compare operating cost, maintenance and recovery after defining that feature. Moving the same server to another provider now preserves the dependency and does not establish reliable scraping.

## Verification backlog (not completed claims)

| Area | Required cases |
|---|---|
| Recovery | Existing DB upgrade; malformed/incompatible store; disk full; interrupted import; export/restore; files missing; deletion failure |
| Library | Empty and 200+ titles; identical names; author/tag search; favourite search; all filter combinations; relaunch persistence; no results; local covers offline |
| AO3 | Single/multiple/ongoing work; source rating variants; long work; notes/formatting expectations; restricted login; challenge/rate limit; removed work; author reorders/removes chapters; retry/cancel |
| Comics | Populated detail; all reading directions; page jump; decimal/non-contiguous chapters; image formats; long strips; zoom/pan; rotation; skip pages; next/previous overscroll; image retry |
| Downloads | Partial page failure; HTTP error body; mismatch page count; cancel; background/resume/relaunch; concurrent stories; replacement failure; interrupted staging; storage limit |
| Bookmarks/progress | Start/middle/end; reflow; source edit; deleted chapter; passage note; chapter/page bookmark; jumping ahead does not imply reading; background/foreground session accounting |
| Activity | Queued/running/partial/failed/completed; local and optional companion; retry; cancel vs dismiss; clear history; unavailable source/backend |
| Accessibility | VoiceOver labels/order/hidden views; maximum Dynamic Type; reduced motion; contrast; keyboard/switch access; target sizes |
| Product validation | Small/large iPhone; iPad; network loss; real-device memory/energy; release configuration; no obligatory localhost/OCI call |

Use existing checks and simulator/manual verification initially. This review did not add tests or run a new build because it changed documentation only. Any new automated coverage should target these failure boundaries rather than mirror implementation details.

## Source map

Paths relative to repository root; current working tree, not a clean release snapshot:

- Shell/startup: `ios/Astral/AstralApp.swift`, `ios/Astral/App/RootView.swift`, both feature `*TabView.swift` and `*SidebarView.swift`.
- Feature screens: `ios/Astral/Packages/{ComicFeature,FanficFeature}/Sources/*/{Library,Browser,Reader,Scrapes,Stats}/`.
- Downloads/imports: each feature `Services/`; fanfic `Resources/AO3Import.js`.
- Models/recovery: `ios/Astral/Packages/Core/Sources/Core/{Models,Services}/`.
- Network/deletion/background transfer: `ios/Astral/Packages/Networking/Sources/Networking/`.
- Stats: `ios/Astral/Packages/StatsUI/Sources/StatsUI/{SharedStatsView,StatsData,HeatmapDayDetailSheet}.swift`.
- Design/accessibility: `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/`.
- Legacy backend: `backend/app/{api/v1/routes,scrapers,tasks}/`, `backend/app/main.py`, `backend/docker-compose.local.yml`.

See the companion [source inventory](2026-10-21-app-ui-source-inventory.md) for navigable view/function/control declarations. It is a traceability aid, not runtime test evidence.
