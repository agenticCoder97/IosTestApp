# AST-15 — Library Filter Refactor — Implementation Plan

**Date**: 2026-04-17
**Branch**: `feature/ast-15-library-filter-refactor`
**Spec**: `docs/superpowers/specs/2026-04-17-ast15-library-filter-refactor-design.md`

---

## Prerequisites

- Read spec before starting any task.
- Each task is a distinct, reviewable commit prefixed `[ios] AST-15`.
- Build and run after every task to catch regressions.
- Do NOT implement multiple tasks in a single commit.

---

## Task 0 — Add `completionStatus` to `LocalComic`

**File to modify**: `ios/Astral/Packages/Core/Sources/Core/Models/LocalComic.swift`

Add one optional property to the `@Model` class:

```swift
/// Story completion status: "ongoing", "complete", or "abandoned". nil = unknown.
public var completionStatus: String? = nil
```

**Placement**: after the existing `archiveStatus` / `isArchived` properties (they're thematically adjacent — both describe a comic's lifecycle state).

**No migration needed**: SwiftData automatically sets the new optional property to `nil` for all existing persisted rows. No `@Attribute` decorator required (not unique, no special behavior).

**Type rationale**: `LocalFanfic.completionStatus` is a non-optional `String` (default `"ongoing"`), but for comics we use `String?` so that existing rows don't silently inherit a wrong status the scraper never provided.

**Commit message**: `[ios] AST-15 add completionStatus to LocalComic`

**Verification**: Project builds. `LocalComic` in Swift REPL (or a unit test) shows `completionStatus` is nil by default on a fresh instance.

---

## Task 1 — Extract shared filter UI primitives to DesignSystem

**Files to create**:
- `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterSectionCard.swift`
- `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterChips.swift` (StatusChip + ToggleChip)
- `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterTextField.swift`
- `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FlowLayout.swift`
- `ios/Astral/Packages/DesignSystem/Sources/DesignSystem/Components/LibraryFilter/FilterSortDirectionToggle.swift`

**What to extract**: The private helpers currently in `FanficFilterView.swift`:
- `FlowLayout` (the custom Layout) → `FlowLayout.swift` (made public)
- `filterSection` view builder → `FilterSectionCard` (generic, takes title + content)
- `statusChip` → `FilterStatusChip`
- `toggleChip` → `FilterToggleChip`
- `filterField` → `FilterTextField`
- Sort direction HStack → `FilterSortDirectionToggle`

**After**: Update `FanficFilterView` to use the new DesignSystem components. Remove the private helpers.

**Verification**: Fanfic filter sheet still renders identically.

---

## Task 2 — Define `FanficFilterPrefs` + persistence in `FanficFilterState`

**File to create**: `ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Library/FanficFilterPrefs.swift`

```swift
struct FanficFilterPrefs: Codable {
    var fandom: String = ""
    var completionStatus: String? = nil
    var wordCountMin: Int? = nil
    var wordCountMax: Int? = nil
    var selectedRatings: [String] = []
    var selectedWarnings: [String] = []
    var characters: String = ""
    var relationship: String = ""
    var sourceKey: String? = nil
    var sortBy: String = FanficSortOption.lastRead.rawValue
    var sortAscending: Bool = false
}
```

**File to modify**: `FanficLibraryView.swift`

- Replace `@State private var filterState = FanficFilterState()` with an `@AppStorage("fanfic.filter.v1")` property holding a JSON string, plus an `@State` `FanficFilterState` loaded from it on appear.
- Add `onChange(of: ...)` observers (or a single onChange on a stable snapshot) that encode `filterState` back to `@AppStorage`.
- Alternatively: initialize `FanficFilterState` from decoded prefs in a custom init and write back in a debounced task.

**Recommended implementation pattern**:
```swift
@AppStorage("fanfic.filter.v1") private var filterPrefsJSON: String = ""
@State private var filterState: FanficFilterState = FanficFilterState()

// in .onAppear or .task:
if let data = filterPrefsJSON.data(using: .utf8),
   let prefs = try? JSONDecoder().decode(FanficFilterPrefs.self, from: data) {
    filterState.load(from: prefs)
}

// in .onChange(of: filterState.sortBy) etc — or use a single @Observable tracking:
.onChange(of: filterState.snapshotForPersistence) { _, new in
    if let data = try? JSONEncoder().encode(new),
       let str = String(data: data, encoding: .utf8) {
        filterPrefsJSON = str
    }
}
```

Add `load(from:)` and `snapshotForPersistence` to `FanficFilterState`.

**Also in this task**: Add `case lastRead = "Last Read"` to `FanficSortOption` and update the sort switch in `filteredFanfics`:
```swift
case .lastRead:
    return result.sorted { ascending
        ? ($0.lastReadAt ?? .distantPast) < ($1.lastReadAt ?? .distantPast)
        : ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
    }
```

**Verification**: Set a filter → kill app → relaunch → filter state is restored.

---

## Task 3 — Define `ComicFilterPrefs` + `ComicFilterState`

**Files to create**:
- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterPrefs.swift`
- `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterState.swift`

```swift
// ComicFilterPrefs.swift
struct ComicFilterPrefs: Codable {
    var showArchived: Bool = false
    var completionStatus: String? = nil       // "ongoing" / "complete" / "abandoned" / nil = all
    var tagsKeyword: String = ""             // case-insensitive substring match on tagsJSON
    var category: String? = nil
    var sourceKey: String? = nil
    var sortBy: String = ComicSortOption.lastRead.rawValue
    var sortAscending: Bool = false
}

// ComicFilterState.swift
enum ComicSortOption: String, CaseIterable {
    case lastRead = "Last Read"
    case dateAdded = "Date Added"
    case title = "Title"
    case chapters = "Chapters"
}

@Observable
final class ComicFilterState {
    var showArchived: Bool = false
    var completionStatus: String? = nil       // nil = all
    var tagsKeyword: String = ""             // "" = no filter
    var category: String? = nil
    var sourceKey: String? = nil
    var sortBy: ComicSortOption = .lastRead
    var sortAscending: Bool = false

    var isActive: Bool {
        showArchived || completionStatus != nil || !tagsKeyword.isEmpty
            || category != nil || sourceKey != nil || sortBy != .lastRead
    }

    func reset() {
        showArchived = false
        completionStatus = nil
        tagsKeyword = ""
        category = nil
        sourceKey = nil
        sortBy = .lastRead
        sortAscending = false
    }

    func load(from prefs: ComicFilterPrefs) { ... }
    var snapshotForPersistence: ComicFilterPrefs { ... }
}
```

**File to modify**: `ComicTabView.swift` — add `filterState: ComicFilterState` to `ComicNavigation`:
```swift
@Observable
final class ComicNavigation {
    ...
    var filterState = ComicFilterState()
}
```

---

## Task 4 — Build `ComicFilterView`

**File to create**: `ios/Astral/Packages/ComicFeature/Sources/ComicFeature/Library/ComicFilterView.swift`

Structure mirrors `FanficFilterView` using the DesignSystem components from Task 1.

Sections:
1. **Sort** — `ComicSortOption` chips + `FilterSortDirectionToggle`
2. **Status** — "Show Archived" toggle chip; completion status chips: All / Ongoing / Complete / Abandoned (bound to `filterState.completionStatus`; selecting "All" sets it to nil)
3. **Tags** — `FilterTextField` bound to `filterState.tagsKeyword`; label: "Tags contain…"; filter logic in `ComicLibraryView.displayedComics` uses `.localizedCaseInsensitiveContains` on `tagsJSON ?? ""`; intentionally no JSON parsing — raw substring match only
4. **Category** — `FilterTextField` bound to `filterState.category`
5. **Source** — chips: All / nhentai / toongod / hentai20

**In `ComicLibraryView.displayedComics`**, add the two new filter clauses after the existing archive filter:
```swift
if let status = filter?.completionStatus {
    ready = ready.filter { $0.completionStatus == status }
}
if !filter.tagsKeyword.isEmpty {
    ready = ready.filter {
        ($0.tagsJSON ?? "").localizedCaseInsensitiveContains(filter.tagsKeyword)
    }
}
```

**File to modify**: `ComicTabView.swift`

Replace `ComicFilterSheet` (the stub) with `ComicFilterView`:
```swift
.sheet(isPresented: $showFilter) {
    ComicFilterView(filterState: navigation.filterState)
        .presentationDetents([.medium, .large])
}
```

Add `isActive` badge dot to filter toolbar button when `navigation.filterState.isActive`:
```swift
Image(systemName: navigation.filterState.isActive
    ? "line.3.horizontal.decrease.circle.fill"
    : "line.3.horizontal.decrease.circle")
    .foregroundStyle(navigation.filterState.isActive ? AstralColors.gold : AstralColors.body)
```

---

## Task 5 — Wire `ComicFilterState` into `ComicLibraryView`

**File to modify**: `ComicLibraryView.swift`

Add `@Environment(\.comicNavigation) private var comicNavigation` (already used in `ComicDetailView`).

Replace the `displayedComics` computed property to apply filter state:
```swift
private var displayedComics: [LocalComic] {
    let filter = comicNavigation?.filterState
    var ready = allComics.filter { $0.totalChapters > 0 && $0.title != "Pending scrape..." }

    if filterFavourites { ready = ready.filter { $0.isFavorite } }

    if !(filter?.showArchived ?? false) {
        ready = ready.filter { !$0.isArchived }
    }
    if let cat = filter?.category, !cat.isEmpty {
        ready = ready.filter { ($0.category ?? "").localizedCaseInsensitiveContains(cat) }
    }
    if let src = filter?.sourceKey {
        ready = ready.filter { $0.sourceKey == src }
    }
    if !searchText.isEmpty {
        ready = ready.filter { ... } // existing search logic
    }

    let ascending = filter?.sortAscending ?? false
    switch filter?.sortBy ?? .lastRead {
    case .lastRead:
        return ready.sorted { ascending
            ? ($0.lastReadAt ?? .distantPast) < ($1.lastReadAt ?? .distantPast)
            : ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
    case .dateAdded:
        return ready.sorted { ascending ? $0.addedAt < $1.addedAt : $0.addedAt > $1.addedAt }
    case .title:
        return ready.sorted { ascending ? $0.title < $1.title : $0.title > $1.title }
    case .chapters:
        return ready.sorted { ascending ? $0.totalChapters < $1.totalChapters : $0.totalChapters > $1.totalChapters }
    }
}
```

**Note**: The existing `ready.sorted { lhs, rhs in if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }...}` logic at the bottom of the current implementation should be removed — archive sorting is now handled by the filter state.

---

## Task 6 — Add persistence to `ComicFilterState` via `@AppStorage`

**File to modify**: `ComicTabView.swift` or `ComicLibraryView.swift`

Follow the same pattern as Task 2 for Fanfic:
- `@AppStorage("comic.filter.v1")` JSON string on `ComicTabView`
- Decode on appear → `navigation.filterState.load(from:)`
- `onChange` → encode back to `@AppStorage`

---

## Task 7 — Lift `FanficFilterState` to `FanficNavigation` + add toolbar badge

**Decision**: Confirmed by user — lift `FanficFilterState` from `FanficLibraryView` to `FanficNavigation` so the toolbar badge has access to `isActive`. This mirrors the comic-side pattern exactly.

**Files to modify**:

### `FanficNavigation` (wherever it is defined — check `FanficTabView.swift` or a dedicated file)

Add property:
```swift
var filterState = FanficFilterState()
```

### `FanficLibraryView.swift`

**Remove**: `@State private var filterState = FanficFilterState()`

**Add**: read `filterState` from `fanficNavigation` (already in environment):
```swift
@Environment(FanficNavigation.self) private var fanficNavigation
// replace all filterState references with fanficNavigation.filterState
```

The `@AppStorage` persistence wiring (Task 2) should move to `FanficTabView` (alongside the `@AppStorage` for `ComicTabView`) so persistence is co-located with ownership:
```swift
// FanficTabView.swift
@AppStorage("fanfic.filter.v1") private var filterPrefsJSON: String = ""
// decode on appear → fanficNavigation.filterState.load(from:)
// onChange → encode back
```

### `FanficTabView.swift`

Add toolbar badge, identical shape to comic side:
```swift
Image(systemName: fanficNavigation.filterState.isActive
    ? "line.3.horizontal.decrease.circle.fill"
    : "line.3.horizontal.decrease.circle")
    .foregroundStyle(fanficNavigation.filterState.isActive ? AstralColors.gold : AstralColors.body)
```

**Binding thread**: `FanficFilterView` already accepts a `filterState` argument — pass `fanficNavigation.filterState` from the sheet call site in `FanficTabView`.

**Commit message**: `[ios] AST-15 lift FanficFilterState to FanficNavigation, add toolbar badge`

---

## Task 8 — Tests

**Files to create/modify**:
- `ios/Astral/Packages/FanficFeature/Tests/FanficFeatureTests/FanficFilterPrefsTests.swift`
- `ios/Astral/Packages/ComicFeature/Tests/ComicFeatureTests/ComicFilterPrefsTests.swift`

Tests:
- `FanficFilterPrefs` encode → decode round-trip preserves all fields
- `ComicFilterPrefs` encode → decode round-trip preserves all fields
- `FanficSortOption.allCases` contains `.lastRead`
- `ComicSortOption.allCases` contains `.lastRead`
- `FanficFilterState.isActive` returns false on default prefs, true when any field set
- `ComicFilterState.isActive` returns false on default prefs, true when any field set

---

## Acceptance Criteria

- [ ] Filter state for both libraries survives app restart
- [ ] Comic library respects sort (Last Read / Date Added / Title / Chapters) and direction
- [ ] Comic library can filter by archive status, completionStatus, tags keyword, category, source
- [ ] Comic `tagsKeyword` filter uses case-insensitive substring match on raw `tagsJSON` — no JSON parsing
- [ ] Fanfic library sort includes "Last Read" option
- [ ] Filter toolbar button shows active indicator (gold `line.3.horizontal.decrease.circle.fill`) on **both** tab bars when non-default filters applied
- [ ] `FanficFilterState` owned by `FanficNavigation` (not `FanficLibraryView`)
- [ ] Reset button clears all filters to defaults
- [ ] Both `FanficFilterPrefs` and `ComicFilterPrefs` have round-trip Codable tests passing
- [ ] `LocalComic.completionStatus` is `String?`, defaults to nil on existing rows
- [ ] No hardcoded hex colors added (all from `AstralColors`)
- [ ] `project.yml` updated and `xcodegen generate` run after new files are added to packages
- [ ] Build succeeds: `xcodebuild -scheme Astral -sdk iphonesimulator ... build`

---

## File Checklist

| File | Action | Task |
|---|---|---|
| `Core/Models/LocalComic.swift` | Modify (add `completionStatus: String?`) | Task 0 |
| `DesignSystem/Components/LibraryFilter/FlowLayout.swift` | Create | Task 1 |
| `DesignSystem/Components/LibraryFilter/FilterSectionCard.swift` | Create | Task 1 |
| `DesignSystem/Components/LibraryFilter/FilterChips.swift` | Create | Task 1 |
| `DesignSystem/Components/LibraryFilter/FilterTextField.swift` | Create | Task 1 |
| `DesignSystem/Components/LibraryFilter/FilterSortDirectionToggle.swift` | Create | Task 1 |
| `FanficFeature/Library/FanficFilterPrefs.swift` | Create | Task 2 |
| `FanficFeature/Library/FanficFilterView.swift` | Modify (use DS components, add lastRead sort) | Task 1 |
| `FanficFeature/Library/FanficLibraryView.swift` | Modify (remove local filterState, use nav) | Task 7 |
| `FanficFeature/FanficTabView.swift` | Modify (own filterState on nav, persistence, active badge) | Task 7 |
| `ComicFeature/Library/ComicFilterPrefs.swift` | Create (includes completionStatus + tagsKeyword) | Task 3 |
| `ComicFeature/Library/ComicFilterState.swift` | Create (includes completionStatus + tagsKeyword) | Task 3 |
| `ComicFeature/Library/ComicFilterView.swift` | Create (Status + Tags + Category + Source sections) | Task 4 |
| `ComicFeature/Library/ComicLibraryView.swift` | Modify (wire filter state incl. completionStatus + tagsKeyword) | Task 5 |
| `ComicFeature/ComicTabView.swift` | Modify (replace stub, filterState on nav, persistence, active badge) | Task 4+6 |
