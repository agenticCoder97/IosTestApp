import XCTest

/// Page object for the MorphLandingView (app launch screen).
struct LandingScreen {
    let app: XCUIApplication

    var comicOrb: XCUIElement { app.otherElements["landing.comic_orb"] }
    var fanficOrb: XCUIElement { app.otherElements["landing.fanfic_orb"] }

    /// Taps the Comics orb to enter the comic tab.
    @discardableResult
    func selectComics() -> ComicLibraryScreen {
        comicOrb.waitAndTap()
        return ComicLibraryScreen(app: app)
    }

    /// Taps the Fan Fiction orb to enter the fanfic tab.
    @discardableResult
    func selectFanfic() -> FanficLibraryScreen {
        fanficOrb.waitAndTap()
        return FanficLibraryScreen(app: app)
    }
}
