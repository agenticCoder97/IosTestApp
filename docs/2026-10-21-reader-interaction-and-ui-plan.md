# Astral reader interactions and UI integration plan

Second review: 21 October 2026. Requested focus: reader interactions, UI integration and look and feel. The original review below records the proposed changes. Implementation and verification are tracked in [the rebuild implementation report](2026-10-21-rebuild-implementation.md).

Companion: [full app review](2026-10-21-app-review-and-rebuild-plan.md). User decision, 21 October: **keep pull-to-next-chapter.** A deliberate pull that begins at a chapter edge, crosses the threshold and is released may change chapters. Ordinary scrolling, momentum and layout changes must not do so. This decision supersedes the earlier recommendation to remove pulling. Keep the data-protection work from the broader plan as a prerequisite to schema changes.

## 1. Direction

Reading should feel stable and deliberate. Scrolling moves content. Swiping turns comic pages. Changing chapters is a deliberate action: a named button or a completed edge pull. The reader must never make someone wonder whether another drag will move a page, pan an image, reveal controls, bookmark text, or leave the chapter.

Preserve the useful comic reading modes and fanfic typography. Keep Astral's dark/gold identity provisionally, but simplify the presentation: stronger text hierarchy, fewer boxed sections, less animation, and controls that appear where their effects happen.

## 2. Second-pass findings

| Finding | Evidence | Impact |
|---|---|---|
| Three different chapter-transition contracts | Comic `webtoonReader` fires an edge-pull trigger; `pagedReader` has button sentinels; fanfic changes chapter on horizontal scroll-position change | Similar gestures produce different outcomes across modes |
| Edge trigger depends on screen geometry | `NextChapterTrigger` uses `UIScreen.main.bounds.height` and global frame; 120pt threshold, timer state and delayed transition remain | Brittle around safe areas, rotation, short chapters and layout changes; geometry-dependent state for an interaction the user wants to retain |
| Trigger comments and behavior diverge | Comments describe a held/armed gate; current parent uses `shouldFire` without that gate | Tuning the ring/arm delay does not reliably describe the actual interaction |
| Paged transition screen shows a spinner before a request starts | `chapterTransitionPage` contains unconditional `ProgressView` inside a button | Suggests work is in progress while the UI is waiting for input |
| Fanfic can change chapter on a sideways drag | Outer horizontal pager calls `navigateTo` when placeholder becomes selected | A diagonal reading gesture can have a much larger consequence than intended |
| Hidden chrome requires long press | Both readers start with chrome hidden and use long press; fanfic paragraphs also have a long-press bookmark action | Discovery problem and conflicting gesture ownership; overlap reproduced during first review |
| Prose runs behind the Dynamic Island | Rechecked live fanfic reader with controls hidden | Reading surface ignores the safe area, not just its background |
| Hardcoded reader chrome offsets | Top padding 56, bottom padding 34, slide offsets -110/+130 | Layout assumes one device geometry; larger text and landscape need real safe-area layout |
| Reader top bar is overcrowded | Source: back, two title lines, chapter count, favourite, comic bookmark and settings; many 28pt icon frames | Important navigation competes with infrequent actions and truncated titles |
| Right-to-left mode reverses page arrays | `pagedReader` enumerates reversed arrays using visual indices | Direction/position mapping needs explicit logical identity; inspect start/resume/bookmarks before calling RTL correct |
| Zoom competes with navigation | `ZoomablePageView` uses simultaneous pinch and conditional drag; panning offsets are not clamped | Image can be moved away; parent gestures need explicit suppression while zoomed |
| Read action follows dense metadata | Live fanfic detail puts summary, source stats and many horizontally scrolling tag rows before Continue | Primary task is visually subordinate; metadata chips and warnings are clipped |
| Import state is not integrated with the rest of the UI | AO3 browser success switches to Library; Scrapes tracks server jobs; two detail controls reimport | Users cannot follow one coherent Add → progress → Read journey |
| Position and completion feed UI incorrectly | Chapter-number ratios and paragraph appearance callbacks drive bars, Continue Reading and statistics | Polishing those displays alone would make inaccurate information more prominent |

Live inspection in this pass: fanfic library → detail → resumed reader and chapter footer on iPhone 17 Pro simulator. Comics gestures were traced in source; no populated comic was available in this simulator, so their current tactile behavior was not newly verified. Visual assessments are not measured contrast or device-performance results.

## 3. Reader interaction contract

### Chapter boundaries: deliberate pull and explicit controls

**Correction after user feedback, 21 October:** preserve pull-to-next-chapter at the actual content boundary. The added end-of-chapter panels/pages were not requested and are removed. No extra reading page, interstitial or footer is inserted after the final image/paragraph.

**Webtoon and fanfic:** begin a new drag at the chapter edge, pull beyond the threshold and release to change chapters. Retreating cancels it. A fling begun inside the chapter cannot change chapters. Auto-scroll stops at the content boundary.

**Paged comics:** retain only actual source pages. Pull beyond the first/last page and release to change chapters, following LTR/RTL source order. There are no transition sentinel pages. Logical page identity, saved position and page count remain source based.

Named Next/Previous chapter, Chapters and explicit completion actions remain in the existing reader controls. The pull hint appears only while pulling.

- A tap starts one transition. Disable duplicate taps while loading; show a spinner only during actual work.
- Keep old chapter and position until new content is ready. On failure, retain the current content with Retry and Back; never strand the reader on a blank new chapter.
- Next chapter missing locally: show **Download next chapter** if the source supports it. If offline, show “Connect to download” plus Retry when appropriate. If the source needs browser interaction, use **Open source to import**. Do not silently request the unavailable legacy backend for local sources.
- At the last available chapter, do not insert an extra page. Completion stays an explicit action in More; checking for updates stays a user action in story detail.
- Reading position, last-page visibility and explicit finished status remain distinct. Merely reaching the last page or opening the final chapter does not mark the story finished.
- Going back to a chapter already visited restores its saved position; provide **Start chapter over** in the chapter menu. A never-opened chapter starts at the beginning. Provide a brief **Back to previous position** action after a deliberate jump.
- Keep a contextual pull/release hint while a deliberate pull is in progress. No arming timers, countdowns, automatic chapter advance or continuous multi-chapter mode in the initial rebuild. Reconsider optional continuous reading only after the explicit model is proven and requested.

### Gesture ownership

| Input | Fanfic | Webtoon | Paged comic |
|---|---|---|---|
| Vertical drag | Scroll prose; deliberate edge pull changes chapter | Scroll pages; deliberate edge pull changes chapter | Pan only when zoomed |
| Horizontal drag | No chapter navigation | No chapter navigation; pan when zoomed | Turn page at base zoom; deliberate edge pull changes chapter; pan while zoomed |
| Single tap, noninteractive content | Toggle controls | Toggle controls | Toggle controls |
| Double tap | Reserved for text interaction; must not toggle chrome twice | Zoom/reset | Zoom/reset |
| Long press | Passage bookmark/context action; later native selection | No global chrome action | No global chrome action |
| Pinch | No navigation action | Zoom | Zoom |
| Named Next/Previous chapter button | Explicit transition | Explicit transition | Explicit transition |

Tap recognition must wait for double-tap resolution on comic images. Taps on links, selection, buttons, sliders and open menus are consumed by those elements, not the background recognizer. Zoomed panning must not turn pages, and offsets must keep content reachable. Reset zoom when explicitly changing pages/chapters; preserve it through a temporary controls overlay.

Show controls on reader entry. Hide only after deliberate content tap or clear reading scroll, never while a sheet, selection, download error or accessibility focus is active. Provide a VoiceOver “Show reader controls” action and an **Always show controls** preference. No timed auto-hide in the first iteration.

### Controls and sheets

```text
‹ Back       Chapter title                  •••

                 Reading content

Chapters        Page 8 of 24 / 42%          Aa / Display
```

- Back returns to the exact originating library/detail/bookmark route, preserving its filters and scroll position. The existing Back control exits the reader.
- Bottom toolbar prioritizes Chapters, position and reading settings. Keep its order consistent across reader types. In fanfic use chapter percentage; in comics use logical page count. Include chapter number in the title/accessible position label so the two are not confused.
- Move Favourite, Bookmark current position, Previous/Next chapter and Start chapter over into a labeled More menu. Passage bookmarking remains directly accessible by context action. End-section Next remains the primary chapter transition.
- Chapter picker is a sheet showing title, order, current position and local availability. Separate unavailable from unread; opening the sheet does not alter progress.
- Use a settings sheet with Done and Reset rather than a large panel replacing the bottom bar. Keep typography preview, font, size, spacing, margins and theme for fanfic; mode, skip pages, brightness, auto-scroll and orientation for comics.
- Save settings immediately, preserve the visible content anchor through reflow, and treat sheet dismissal as dismissal—not navigation. Pause auto-scroll while controls/sheets are open, on backgrounding, at errors and at chapter end. Resume only through an explicit action.
- Use actual safe-area insets. Background may bleed edge-to-edge; prose, buttons and page captions must not sit behind the island or home indicator. Avoid viewport jumps when chrome appears by keeping content geometry stable and overlaying safe-area-aware controls with enough readable inset.

## 4. Look and feel

| Area | Proposed treatment | Acceptance |
|---|---|---|
| Overall tone | Quiet reading utility; dark/gold as accent rather than gold on every label | Content and primary action dominate; no decorative status dots |
| Type | Semantic text styles for app chrome; reader size remains user-adjustable with scaling policy | Largest supported text size keeps actions reachable; important text does not truncate without a way to read it |
| Surfaces | One background, modestly elevated controls/sheets, fewer card-within-card groups | Grouping follows function; no decorative container around every statistic |
| Reader contrast | Readable body text and secondary labels for each theme; opaque/material toolbar legibility over images | Measure contrast in implementation; verify dark, sepia, paper and bright comic panels |
| Targets | At least 44×44pt interactive areas even when glyphs are smaller | One-handed use and VoiceOver names work; controls don't depend on fine dragging |
| Progress | Position in the bottom control; optional unobtrusive indicator inside safe bounds | No always-on gold line across the island; no inaccurate completion claims |
| Motion | Brief fade for chrome and chapter replacement; normal page movement | Remove page shrink/fade decoration, springy title shifts and automatic list-entry choreography on routine navigation; reduced motion respected |
| Haptics | One acknowledgement for intentional bookmark/chapter action, optional | No edge-arming haptic or tick on every scrubber intermediate value |
| Feedback | Inline status beside the action; persistent actionable errors; short success confirmation | Loading only while work runs; not merely because a transition card is displayed |

## 5. UI integration across the app

### Library → detail → reader

- Keep the broader plan's Library/Add/Activity/Settings navigation; preserve independent Comics/Fanfic scope and navigation state.
- Continue Reading opens the saved position directly. A library row opens detail. Label both so the distinction is intentional.
- Detail order: title/author/source → Read/Resume and local availability → Chapters/Bookmarks → expandable summary and metadata. Keep rating and warnings visible without clipping; secondary fandom/free tags may collapse with “Show all”. Source warnings must remain accessible before reading.
- Move update/import actions into one named control. “Downloaded” is status, not a button that unexpectedly removes content. Remove Downloads is a separate storage action explaining what remains.
- Reduce row information to title, author/source, useful count and reading position. Source engagement and full summary belong in detail. Use readable placeholder covers rather than large empty decorative artwork regions.
- Metadata link opens a meaningful local search with matching semantics; preserve a Back path to the story. Favourites and filters must not silently change the search scope.

### Add → activity → ready to read

- Browser shows source and a labeled **Import work**/**Import comic** action; explain disabled state (“Open a work first”). Separate browser URL entry from library search.
- After submission, show progress inline and in shared Activity. Once successful, offer **Read now** and **View in library**. Do not automatically throw the user out of browsing.
- Current AO3 extraction is tied to a live WKWebView. First implement honest foreground import behavior: retain the browser while importing and give safe cancellation. Allow unrestricted navigation only after extraction/job ownership is independent of the view lifecycle.
- Preserve source tab/session and URL when moving among primary destinations. Errors keep the relevant source page and saved copy intact.
- FFNet/legacy sources must expose their actual availability; do not imply that an import button works without its required companion.

### Activity, storage and statistics

- Activity contains import/download jobs, with Cancel, Retry, Open and dismiss-history actions that do different things. Avoid raw worker terminology in primary UI.
- Storage is the only ordinary place for bulk removal and compression. Show bytes and which copies will remain. Reader controls should not modify storage unexpectedly.
- Stats becomes secondary reading history with clear All/Comics/Fanfic scope. Fix measurement before visual polish. No duplicated stats destination or global search/filter toolbar that has no effect there.

## 6. Implementation sequence

| Priority / slice | Changes | Main code locations | Completion gate |
|---|---|---|---|
| P1 / A: deliberate chapter navigation | Remove added end panels; replace global-screen webtoon triggers/timers with release-gated edge pulling at actual content boundaries; use the same pull contract in fanfic and LTR/RTL comics; remove fanfic horizontal chapter pager; route chapter requests through one guarded transition path | Both `Reader/*ReaderView.swift`; shared component in DesignSystem, state logic kept outside visual component | Momentum, diagonal reading swipes, layout and auto-scroll never change chapter; a deliberate edge pull does; Next loads once; failure retains current content |
| P1 / B: readable and discoverable reader | Safe areas; visible initial controls; exclusive tap/double-tap/long-press handling; zoom bounds; persistent error escape | Both readers, `ZoomablePageView`, `ReaderMotion` | No island/home-indicator overlap; bookmark doesn't toggle controls; pan doesn't navigate; Back always works |
| P1 / C: dependable position | Stable chapter/page identity; viewport anchor tracking; logical RTL mapping; separate completion; preserve old chapter until new one is ready | Reader navigation/load/persist functions; Core reading-state models as required | Start/middle/end resume correct in every mode; RTL starts on intended first page; reflow and failed navigation preserve anchor |
| P2 / D: coherent reader tools | Shared control layout, chapter sheet availability, labeled More menu, settings sheet, auto-scroll pause/resume policy | Reader toolbar/settings/chapter-sheet subviews; DesignSystem | Same control means same thing in both readers; sheets cannot cause accidental chapter movement |
| P2 / E: reading entry and import continuity | Detail hierarchy; compact library; named update/storage actions; Add/activity integration; route/session preservation | Feature Library, Browser, TabView files; import service/job state | Resume is immediate; Add → progress → Read has a clear path; returning restores prior context |
| P2 / F: visual/accessibility finish | Semantic typography/colors, minimum hit areas, labels/selected states, reduced motion, scoped toolbars, measured contrast | DesignSystem plus affected feature views | Small/large phone, landscape and large text work; VoiceOver can operate every reading action |

Implement these as small reviewable changes. Do not bundle navigation replacement, schema migration and cosmetic restyling into one patch. Preserve existing user changes in the readers. Back up local content before any reading-state schema migration; add a recoverable migration path before altering models.

For runtime verification, obtain a local comic sample with at least two chapters and a long page, plus a one-page chapter. This is required for runtime proof, not a reason to run a permanent backend. Existing Docker or a temporary local fixture/import harness can supply it; distinguish fixture proof from live-source import proof.

## 7. Acceptance scenarios

1. Fling from within webtoon/fanfic; chapter ID remains unchanged. Begin a new edge drag, exceed the threshold and release; one chapter change occurs. Retreat below threshold before release; no change occurs. Paged readers contain exactly the source pages; pulling beyond the last source page changes chapter only after threshold and release.
2. Tap Next twice; only one transition. Disconnect during load; current chapter/anchor remains available, with Retry and Back. Reconnect and retry successfully.
3. End of ongoing work says caught up; end of completed work offers Mark finished. Opening the last chapter alone does not mark completion.
4. Fanfic diagonal scroll does not navigate. Long press opens passage action only. Tapping a button/link/selection does not toggle reader chrome.
5. Single tap toggles controls; comic double tap zooms without intermediate chrome flash. While zoomed, drag pans within bounds rather than turning pages.
6. Return from chapters/settings/bookmark sheet to the same visible content. Changing font/margins or rotating preserves a stable content anchor.
7. Read LTR and RTL using known numbered pages; page number, slider, bookmarks and resume identify the same source page. End section is excluded from counts.
8. Auto-scroll stops at chapter boundary, on background, on sheet opening and on failure. It never advances chapters or resumes without deliberate input.
9. Back returns to originating filtered library/detail route. Continue Reading goes straight to the saved position. Chapter jump offers a route back to previous position.
10. Dark/sepia/paper, long titles, largest text and landscape: readable content, no clipped essential controls, no unsafe-area overlap. VoiceOver can reveal controls, navigate chapters and identify availability.
11. Import completion offers Read now/View in library and retains browser context. Cancellation and errors keep prior content; local Activity reflects the same job.

Use existing checks and hands-on simulator/device verification for the implementation; no new tests were added in this planning pass. Populated comics, physical-device gesture feel, VoiceOver and measured contrast remain verification work. A source review is not enough to declare those scenarios passed.

## 8. First implementation target

Start with **A + the safe-area/gesture essentials of B**, with the position work needed to prevent regressions from C. This directly addresses the reported dissatisfaction. Validate one fanfic and one comic end-to-end before expanding into shell changes or broad restyling.

Success is simple: reading stays in the current chapter until the user chooses to leave it; the next action is obvious, reachable and reversible; the interface never covers the content it is meant to present.
