import Foundation

/// Centralized accessibility identifiers for UI testing.
/// Used by views via `.accessibilityIdentifier()` and by XCUITest queries.
public enum AccessibilityID {
    // MARK: - Landing
    public static let landingComicOrb = "landing.comic_orb"
    public static let landingFanficOrb = "landing.fanfic_orb"

    // MARK: - Tab Navigation
    public static let tabMenu = "tab.menu"
    public static let tabComicLabel = "tab.comic_label"
    public static let tabFanficLabel = "tab.fanfic_label"

    // MARK: - Sidebar
    public static let sidebarToggle = "sidebar.toggle"
    public static let sidebarLibrary = "sidebar.library"
    public static let sidebarFavourites = "sidebar.favourites"
    public static let sidebarBrowse = "sidebar.browse"
    public static let sidebarScrapes = "sidebar.scrapes"
    public static let sidebarStats = "sidebar.stats"

    // MARK: - Search
    public static let searchToggle = "search.toggle"
    public static let searchField = "search.field"

    // MARK: - Library
    public static let comicLibrary = "library.comic"
    public static let fanficLibrary = "library.fanfic"
    public static let continueReadingStrip = "library.continue_reading"

    /// Dynamic ID for a story card: `"library.story.<uuid>"`
    public static func storyCard(_ id: UUID) -> String { "library.story.\(id)" }

    // MARK: - Detail View
    public static let detailContinueReading = "detail.continue_reading"
    public static let detailChapterList = "detail.chapter_list"
    public static let detailRescrape = "detail.rescrape"

    /// Dynamic ID for a chapter row: `"detail.chapter.<number>"`
    public static func chapterRow(_ number: Int) -> String { "detail.chapter.\(number)" }

    // MARK: - Reader (shared)
    public static let readerBackButton = "reader.back"
    public static let readerProgressBar = "reader.progress"

    // MARK: - Comic Reader
    public static let comicReaderContainer = "reader.comic.container"
    public static let comicReaderHUD = "reader.comic.hud"
    public static let comicReaderChapterList = "reader.comic.chapter_list"

    // MARK: - Fanfic Reader
    public static let fanficReaderContainer = "reader.fanfic.container"
    public static let fanficReaderSettingsBar = "reader.fanfic.settings"
    public static let fanficReaderChapterOverlay = "reader.fanfic.chapter_overlay"

    // MARK: - Empty States
    public static let emptyState = "empty_state"

    // MARK: - Error Banner
    public static let errorBanner = "error.banner"
}
