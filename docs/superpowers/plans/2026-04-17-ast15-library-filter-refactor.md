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
    var category: String? = nil
    var sourceKey: String? = nil
    var sortBy: ComicSortOption = .lastRead
    var sortAscending: Bool = false

    var isActive: Bool {
        showArchived || category != nil || sourceKey != nil || sortBy != .lastRead
    }

    func reset() {
        showArchived = false
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
2. **Status** — "Show Archived" toggle chip
3. **Category** — `FilterTextField` bound to `filterState.category`
4. **Source** — chips: All / nhentai / toongod / hentai20

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

## Task 7 — Add `isActive` badge to FanficFilterView toolbar button

**File to modify**: `FanficTabView.swift`

Apply the same active-indicator pattern as the Comic side (Task 4).

Check `FanficNavigation`'s access to `filterState.isActive` (the state is in `FanficLibraryView` today — may need to move `FanficFilterState` up to `FanficNavigation` for the toolbar button to see it, same as the Comic pattern).

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
- [ ] Comic library can filter by archive status, category, source
- [ ] Fanfic library sort includes "Last Read" option
- [ ] Filter toolbar button shows active indicator (gold icon) when non-default filters applied
- [ ] Reset button clears all filters to defaults
- [ ] Both `FanficFilterPrefs` and `ComicFilterPrefs` have round-trip Codable tests passing
- [ ] No hardcoded hex colors added (all from `AstralColors`)
- [ ] `project.yml` updated and `xcodegen generate` run after new files are added to packages
- [ ] Build succeeds: `xcodebuild -scheme Astral -sdk iphonesimulator ... build`

---

## File Checklist

| File | Action |
|---|---|
| `DesignSystem/Components/LibraryFilter/FlowLayout.swift` | Create |
| `DesignSystem/Components/LibraryFilter/FilterSectionCard.swift` | Create |
| `DesignSystem/Components/LibraryFilter/FilterChips.swift` | Create |
| `DesignSystem/Components/LibraryFilter/FilterTextField.swift` | Create |
| `DesignSystem/Components/LibraryFilter/FilterSortDirectionToggle.swift` | Create |
| `FanficFeature/Library/FanficFilterPrefs.swift` | Create |
| `FanficFeature/Library/FanficFilterView.swift` | Modify (use DS components, add lastRead sort) |
| `FanficFeature/Library/FanficLibraryView.swift` | Modify (add persistence, lastRead sort case) |
| `FanficFeature/FanficTabView.swift` | Modify (move filterState to FanficNavigation, active badge) |
| `ComicFeature/Library/ComicFilterPrefs.swift` | Create |
| `ComicFeature/Library/ComicFilterState.swift` | Create |
| `ComicFeature/Library/ComicFilterView.swift` | Create |
| `ComicFeature/Library/ComicLibraryView.swift` | Modify (wire filter state) |
| `ComicFeature/ComicTabView.swift` | Modify (replace stub, add filterState to nav, persistence, active badge) |
