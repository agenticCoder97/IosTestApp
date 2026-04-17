# AST-15 — Library Filter Refactor Design Spec

**Date**: 2026-04-17
**Author**: Design agent (autonomous)
**Branch**: `feature/ast-15-library-filter-refactor`
**Status**: Design only — no implementation (user decisions folded in 2026-04-17)

---

## Summary

Both library views (Comic and Fanfic) need a working filter + sort system. Fanfic has a partially-wired `FanficFilterState` and a full `FanficFilterView`, but state is not persisted across launches. Comic has a filter button in the toolbar and a sheet stub ("Comic filters coming soon.") but no filter state or UI. This spec designs a unified approach covering both libraries.

---

## Goals

1. Persist filter/sort state across app launches for both libraries independently.
2. Build `ComicFilterView` to replace the `ComicFilterSheet` stub in `ComicTabView.swift`.
3. Wire `ComicFilterState` into `ComicLibraryView.displayedComics`.
4. Align the FanficFilterState persistence (currently transient) to survive restarts.
5. Add a `lastRead` sort option to both sort enums (absorbs AST-13).
6. Extract shared UI primitives (section card, chips, flow layout) to `DesignSystem`.

---

## Non-Goals

- Changing `@Query` predicate strategy — in-memory filtering is sufficient and intentionally kept.
- Server-side filtering (all filtering is client-side on the local SwiftData store).
- Cross-library "unified" filter state — each library persists independently.
- Any backend changes.

---

## Model Audit

| Filterable Field | LocalFanfic | LocalComic | Category |
|---|---|---|---|
| `isFavorite` | Bool | Bool | **Shared** |
| `isDownloaded` | Bool | Bool | **Shared** |
| `totalChapters` (sort) | Int | Int | **Shared** |
| `addedAt` (sort) | Date | Date | **Shared** |
| `lastReadAt` (sort) | Date? | Date? | **Shared** |
| `progressPercent` (read state) | Double | Double | **Shared** |
| `sourceKey` (filter by source) | String | String | **Shared** |
| `title` (sort) | String | String | **Shared** |
| `completionStatus` | String (ongoing/complete/abandoned) | String? (ongoing/complete/abandoned, nil=unknown) | **Shared** |
| `rating` | String? (G/T/M/E/NR) | — | **Fanfic-only** |
| `fandom` | String? | — | **Fanfic-only** |
| `wordCount` | Int? | — | **Fanfic-only** |
| `warnings` | String? | — | **Fanfic-only** |
| `characters` | String? | — | **Fanfic-only** |
| `pairing` | String? | — | **Fanfic-only** |
| `publishedAt` / `updatedAtSource` (sort) | Date? | — | **Fanfic-only** |
| `freeformTags` | String? | — | **Fanfic-only** |
| `isArchived` | — | Bool (from archiveStatus) | **Comic-only** |
| `category` | — | String? | **Comic-only** |
| `tagsJSON` (keyword search) | — | String? | **Comic-only** |

**Summary**: 9 shared filterable fields, 8 fanfic-only, 3 comic-only.

---

## Unified Filter State Design

### Persistence: `@AppStorage` + `Codable` struct

**Decision**: Use `@AppStorage` with JSON-encoded `Codable` structs rather than a SwiftData `FilterPreferences` @Model row.

**Rationale**:
- Filter state is a UI preference, not application data. It has no relationships or query needs.
- `@AppStorage` + `Codable` requires zero SwiftData schema migrations when filter fields are added.
- A SwiftData singleton row requires careful insert-or-fetch logic and adds noise to the model layer.
- JSON size is negligible (~200 bytes per library).

**Keys**:
- `"fanfic.filter.v1"` → JSON-encoded `FanficFilterPrefs`
- `"comic.filter.v1"` → JSON-encoded `ComicFilterPrefs`

The `v1` suffix allows future breaking changes without corrupting existing prefs (just ignore the old key and start fresh).

### Codable Prefs Structs

```swift
// In FanficFeature package
struct FanficFilterPrefs: Codable {
    var fandom: String = ""
    var completionStatus: String? = nil       // CompletionStatus.rawValue
    var wordCountMin: Int? = nil
    var wordCountMax: Int? = nil
    var selectedRatings: [String] = []        // Array not Set for Codable
    var selectedWarnings: [String] = []
    var characters: String = ""
    var relationship: String = ""
    var sourceKey: String? = nil              // "ao3", "ffnet", nil = all
    var sortBy: String = FanficSortOption.lastRead.rawValue
    var sortAscending: Bool = false
}

// In ComicFeature package
struct ComicFilterPrefs: Codable {
    var showArchived: Bool = false
    var completionStatus: String? = nil       // "ongoing" / "complete" / "abandoned" / nil = all
    var tagsKeyword: String = ""             // case-insensitive substring match on tagsJSON
    var category: String? = nil
    var sourceKey: String? = nil              // "nhentai", "toongod", "hentai20", nil = all
    var sortBy: String = ComicSortOption.lastRead.rawValue
    var sortAscending: Bool = false
}
```

---

## Model Changes

### `LocalComic.completionStatus`

**Type**: `String?` (optional)
**Default**: `nil` (no default value — omitted from init; nil means "unknown / not yet set")
**Raw values**: mirrors `LocalFanfic.completionStatus` — `"ongoing"`, `"complete"`, `"abandoned"`
**No data migration needed**: SwiftData treats a newly added optional property as nil for all existing rows automatically.
**Note**: `LocalFanfic.completionStatus` is a non-optional `String` with a default of `"ongoing"`. For `LocalComic` we use `String?` so that existing library entries don't assume "ongoing" when the scraper never provided a value.

Add to `LocalComic` in `Core` package:
```swift
/// Story completion status: "ongoing", "complete", or "abandoned". nil = unknown.
public var completionStatus: String? = nil
```

No `@Attribute` decorator needed (not unique; no special SwiftData behavior required).

---

### @Observable State Classes (runtime)

The existing `FanficFilterState` (@Observable class) is the runtime source of truth during a session. The prefs struct handles persistence at the boundary:

- On view `init`/`onAppear`: decode `@AppStorage` JSON → populate `FanficFilterState`
- On filter change (`onChange(of: filterState)`): encode `FanficFilterState` → write to `@AppStorage`

This avoids Codable conformance on `@Observable` (which conflicts with `@Bindable`).

### Sort Options

Add `lastRead` to both enums (AST-13 folded in):

```swift
// FanficFeature
enum FanficSortOption: String, CaseIterable {
    case lastRead = "Last Read"     // NEW — AST-13
    case dateAdded = "Date Added"
    case dateUpdated = "Date Updated"
    case wordCount = "Word Count"
    case title = "Title"
    case chapters = "Chapters"
}

// ComicFeature (new)
enum ComicSortOption: String, CaseIterable {
    case lastRead = "Last Read"
    case dateAdded = "Date Added"
    case title = "Title"
    case chapters = "Chapters"
}
```

---

## In-Memory Filtering vs @Query Rebuild

**Decision**: Keep in-memory filtering via computed properties.

**Tradeoff**:

| Approach | Pros | Cons |
|---|---|---|
| In-memory filter | Simple. No macro gymnastics. Works with any predicate complexity. Already in use. | Loads all non-deleted rows into memory (~O(n) on collection size). |
| @Query rebuild | Only fetches matching rows from SQLite. | iOS 17.2 `#Predicate` macro is compile-time only — runtime predicate composition is not supported. Requires view recreation or dynamic binding tricks. High complexity. |

For a single-user sideloaded app, library size is bounded (< 500 titles per library in practice). In-memory filtering at this scale is imperceptible. The `@Query` approach is not viable on iOS 17.2 without significant workarounds (e.g. `NSPredicate` + `ModelContext.fetch` bypassing the macro, which loses type safety).

---

## UI Structure

### Shared DesignSystem Components

Move to `DesignSystem/Sources/DesignSystem/Components/LibraryFilter/`:

- `FlowLayout` (wrapping chip layout) — currently private in `FanficFilterView`
- `FilterSectionCard` — the grey card with a title and content slot
- `FilterStatusChip` — single-select chip (radio style)
- `FilterToggleChip` — multi-select chip with gold border when active
- `FilterTextField` — labelled text field with AstralColors styling
- `FilterSortDirectionToggle` — ascending/descending toggle button

### FanficFilterView (FanficFeature — unchanged structure, refactored to use DesignSystem components)

Sections:
1. **Sort** — sort picker chips + direction toggle (add `lastRead` option)
2. **Work Info** — fandom text field, completion status chips (All/Complete/Ongoing/Abandoned), word count range
3. **Tags** — rating chips (NR/G/T/M/E), warning checkboxes, characters field, relationship field
4. **Source** — source chips (AO3 / FFNet / All)

### ComicFilterView (ComicFeature — new, in `Library/ComicFilterView.swift`)

Sections:
1. **Sort** — sort picker chips + direction toggle
2. **Status** — show archived toggle (default: hide archived); completion status chips (All / Ongoing / Complete / Abandoned) — filters on `completionStatus`
3. **Tags** — `FilterTextField` bound to `filterState.tagsKeyword`; filter logic applies `.localizedCaseInsensitiveContains` on the raw `tagsJSON` string — intentionally simple substring match, no JSON parsing; a future issue will track structured tag-chip UI if ever needed
4. **Category** — category text field (matches `category` field)
5. **Source** — source chips (nhentai / toongod / hentai20 / All)

The `ComicFilterView` replaces `ComicFilterSheet` in `ComicTabView.swift`. The `showFilter` state and sheet attachment remain in `ComicTabView`; the filter state (`ComicFilterState`) must be threaded from `ComicTabView` down to `ComicLibraryView` (via environment or direct binding, same pattern as `fanficNavigation.showFilter`).

### FilterState Architecture (both libraries)

#### Comic side
`ComicFilterState` lives on `ComicNavigation` (already decided). `ComicTabView` owns `ComicNavigation` as an `@State` object, reads `navigation.filterState.isActive` for the toolbar badge, and passes `navigation.filterState` to `ComicFilterView` and `ComicLibraryView`.

#### Fanfic side — lift `FanficFilterState` to `FanficNavigation`

**Decision (user-confirmed)**: Lift `FanficFilterState` from `FanficLibraryView` up to `FanficNavigation` so that the fanfic toolbar button can show the same active-filter badge as the comic side.

**Current state**: `FanficFilterState` is `@State private var` inside `FanficLibraryView`, invisible to `FanficTabView`.

**Target state**:
- Add `var filterState = FanficFilterState()` to `FanficNavigation` (@Observable class).
- `FanficTabView` reads `fanficNavigation.filterState.isActive` to drive toolbar badge.
- `FanficLibraryView` receives `filterState` via the existing `fanficNavigation` environment object instead of owning it locally.
- `FanficFilterView` binding unchanged — it already takes `filterState` by reference.

**Toolbar badge pattern (both libraries)**:
```swift
// In FanficTabView toolbar:
Image(systemName: fanficNavigation.filterState.isActive
    ? "line.3.horizontal.decrease.circle.fill"
    : "line.3.horizontal.decrease.circle")
    .foregroundStyle(fanficNavigation.filterState.isActive ? AstralColors.gold : AstralColors.body)

// In ComicTabView toolbar — identical shape:
Image(systemName: navigation.filterState.isActive
    ? "line.3.horizontal.decrease.circle.fill"
    : "line.3.horizontal.decrease.circle")
    .foregroundStyle(navigation.filterState.isActive ? AstralColors.gold : AstralColors.body)
```

The `isActive` check for `FanficFilterState` must be updated to include `completionStatus != nil` once the fanfic filter gains that field (already present for `ComicFilterState`).

---

## Relationship to AST-13

AST-13 ("default sort by last read") is a subset of this work:
- Adding `lastRead` to `FanficSortOption` and the new `ComicSortOption` directly implements AST-13.
- Making `lastRead` the default value in `FanficFilterPrefs.sortBy` and `ComicFilterPrefs.sortBy` satisfies the "default" requirement.
- AST-13 should be closed as "resolved via AST-15" when this PR merges.

---

## Testing

### Unit tests (Swift Testing, in `Core/Tests` or feature test targets)

- `FanficFilterPrefs` round-trip encode/decode
- `ComicFilterPrefs` round-trip encode/decode
- `FanficSortOption` includes `.lastRead`
- `ComicSortOption` includes `.lastRead`

### UI / Integration tests (manual or Playwright)

- Fanfic: set a filter, kill the app, relaunch — filter state restored
- Comic: set a filter, kill the app, relaunch — filter state restored
- Fanfic: filter by completion status "Complete" — only complete fanfics shown
- Fanfic: filter by rating "E" — only explicit fanfics shown
- Comic: toggle "Show Archived" — archived comics appear/disappear
- Both: sort by Last Read — most recently read item appears first
- Both: Reset button clears all filters

---

## Decisions Made Autonomously

| Decision | Choice | Rationale |
|---|---|---|
| Persistence approach | `@AppStorage` + `Codable` struct | Zero migration risk; filter is a UI preference, not domain data |
| Filter execution | In-memory computed property | `@Query` predicates are compile-time on iOS 17.2; in-memory is sufficient for bounded library size |
| View architecture | Two separate feature views (FanficFilterView, ComicFilterView) sharing DesignSystem primitives | Models differ enough that a generic view adds abstraction without real reuse |
| AST-13 relationship | Fold into AST-15 | `lastRead` sort is a natural line item inside the sort section; keeping it separate wastes a PR |
| ComicFilterState location | Field on `ComicNavigation` | Mirrors FanficNavigation pattern; avoids new environment key |

---

## Confirmed Decisions (user answers, 2026-04-17)

| Question | Decision |
|---|---|
| Add `completionStatus` to `LocalComic`? | **Yes** — `String?` optional, same raw values as `LocalFanfic` ("ongoing"/"complete"/"abandoned"). nil = unknown. No backfill needed. |
| Comic tag filtering approach? | **Keyword-substring on raw `tagsJSON` string** — case-insensitive `.localizedCaseInsensitiveContains`. No JSON parser, no tag-chip UI. Future issue if structured tags are ever needed. |
| Lift `FanficFilterState` to `FanficNavigation`? | **Yes** — both tab views show an active-filter badge (`line.3.horizontal.decrease.circle.fill` in gold) when `filterState.isActive` is true. Mirrors the comic-side pattern. |
| Source filter UX (chips vs Picker)? | **Chips** — consistent with fanfic source filter and all other single-select filters in the sheet. (Autonomous decision, confirmed by omission.) |
