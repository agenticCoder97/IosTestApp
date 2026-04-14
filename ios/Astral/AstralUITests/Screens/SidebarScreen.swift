import XCTest

/// Page object for the sidebar navigation (ComicSidebarView / FanficSidebarView).
struct SidebarScreen {
    let app: XCUIApplication

    // MARK: - Elements

    var libraryItem: XCUIElement { app.buttons["Library"] }
    var favouritesItem: XCUIElement { app.buttons["Favourites"] }
    var browseItem: XCUIElement { app.buttons["Browse"] }
    var scrapesItem: XCUIElement { app.buttons["Scrapes"] }
    var statsItem: XCUIElement { app.buttons["Stats"] }

    // MARK: - Actions

    func tapLibrary() {
        libraryItem.waitAndTap()
    }

    func tapFavourites() {
        favouritesItem.waitAndTap()
    }

    func tapBrowse() {
        browseItem.waitAndTap()
    }

    func tapScrapes() {
        scrapesItem.waitAndTap()
    }

    func tapStats() {
        statsItem.waitAndTap()
    }
}
