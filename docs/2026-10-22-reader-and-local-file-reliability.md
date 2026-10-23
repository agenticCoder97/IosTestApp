# Reader and local-file reliability

22 October 2026. Focus: the core local reading experience. Adult-content source acquisition is outside this pass. Build 348 was installed during the initial delivery attempt. The user subsequently requested completing the code first and deploying later; no further phone actions are being taken while the follow-up candidate is verified.

## Changes

- Comic webtoon positions include the offset within the source page. The reader waits for the image dimensions and scroll view before restoring. Changed viewport, reading mode, skipped pages or page count fall back to the logical page. Explicit page jumps and Start chapter over discard the previous offset; active scrolling cancels a pending restore. Zoom geometry does not replace the reading anchor.
- Webtoon page jumps and exact scrolling now share one position owner. This fixes page labels changing without the content moving and Down one screen jumping backward. Geometry reads a synchronized offset snapshot without crossing actor isolation; initialization cannot discard a saved anchor. Closing unchanged display settings keeps the current position, and resetting the reading mode retains the current source page.
- Comic bookmark lookup and initial bookmark navigation prefer the chapter UUID. Alternate source releases with the same chapter number retain independent bookmarks. Old bookmarks without UUID anchors still use their chapter number.
- Saved-copy removal is disabled for imported local stories, with a service-level guard before any mutation. Reimport currently creates a new story and cannot reconnect retained progress/bookmarks. Storage and missing-content messages now explain this limitation and the full-library backup recovery option.
- Comic folder import rejects a mixture of root images and chapter folders before copying. This prevents a root cover from silently replacing an entire chapter collection. A single validated plan determines both the selected pages and the reserved storage size.
- Explicit SwiftData imports remove the existing app-source compiler warnings in RootView and ComicCardView.
- `AstralSmoke` selects the five existing launch and Add-screen UI tests. Its shared scheme is reproducible from `project.yml`; the pre-existing Astral scheme and signing edits are preserved. The existing Add test binds the native tab bar before loading WebKit, avoiding a failing post-load global accessibility enumeration while retaining live-frame, hittability and Files-picker assertions. No new tests were added.

## Validation

The initial and pre-installation Debug simulator builds passed on iPhone 17 Pro / iOS 26.4. Independent source review and `git diff --check` passed. The first smoke run passed all five tests. On the pre-installation application build, the three launch tests and fanfic Add test passed, while the comic Add test twice hit a remote accessibility snapshot failure at the global tab-bar enumeration. After narrowing that existing test query, both Add tests passed with all assertions retained. Thus all five selected tests passed against that app, with the corrected Add tests run separately. Results are in `/tmp/astral-20261022/AstralSmoke-final.xcresult` and `AstralSmoke-native-query.xcresult`; the failed results are retained rather than relabeled as successful. These runs predate the follow-up reader repairs and do not validate the latest candidate.

The final Debug simulator build passed (`reader-reset-final-build.log`). The final Release build 349 also passed (`release-349-build.log`), with `codesign --verify --deep --strict` succeeding. Only the expected skipped AppIntents metadata warning remains in these app builds. The signed build 349 bundle is `/tmp/astral-20261022/DeviceDerivedData/Build/Products/Release-iphoneos/Astral.app`; it has not been installed on the phone. The earlier build 348 is retained as `/tmp/astral-20261022/installed-build-348.app` and does not contain the later reader repairs.

Build 348 was installed in place on the connected iPhone 16 Pro Max before the user's follow-up instruction to finish the code and deploy later. Device readback confirmed `com.astral.reader`, version 1.0.0, build 348 (previously 347). The subsequent launch request was denied with the explicit device-locked error (`FBSOpenApplicationErrorDomain` code 7). Installation is confirmed; launching and physical reader verification were not completed. Install, version-readback and launch logs are retained under `/tmp/astral-20261022/phone-*`. No further phone installation or launch was performed after the deferral.

Manual simulator verification used the existing local Reader verification sample. The repaired reader demonstrated Page 3 → Page 2 navigation and forward Down one screen movement, followed by exact long-page exit/reopen. Closing unchanged Display settings remained stable after dismissal. Chapter 2.5 opened and Back to previous chapter returned to chapter 1. These checks exposed and resolved the competing scroll ownership and unnecessary settings reload.

On the final installed simulator binary, skip-first-page = 1 resumed source Page 2 at the same position after exit/reopen: the 1200, 1500 and 1800 markers stayed at the same viewport heights. This also exercises exact resume on the first displayed page. Switching to L → R retained source Page 2; selecting Page 3 and resetting back to Webtoon retained Page 3. After restoring skip = 0, Start chapter over followed by exit/reopen showed Page 1 at the beginning. Screenshots are retained under `/tmp/astral-20261022/webtoon-*.png` and `final-skip1-before-reopen.png`. Computer-use drag/wheel input did not move the simulator reader, so these checks used the app's page menus and built-in scroll command; they do not establish touch or pull behavior.

The final-source `AstralSmoke` run passed all five existing tests with zero failures in 52.7 seconds: both Add layouts/Files pickers and all three launch checks. The completed result bundle is `/tmp/astral-20261022/AstralSmoke-verified.xcresult`, with `smoke-verified.log` beside it. The app's final Debug and Release builds, independent source review and `git diff --check` also pass.

Run the maintained smoke checks with an available simulator UDID:

```sh
xcodebuild test -project ios/Astral/Astral.xcodeproj -scheme AstralSmoke \
  -destination 'platform=iOS Simulator,id=<available-UDID>' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

The package schemes still have no configured test actions. The remaining legacy UI tests describe older navigation and are not selected by AstralSmoke. The smoke tests cover launch choreography, the two browser viewports and their Files pickers; they do not prove the reader gesture matrix or every source import.

## Remaining limits

Physical touch/zoom/pull behavior, rotation, radio-off source reading and duplicate-release bookmark interaction still need runtime evidence. Bookmark identity and local-file guards were source-reviewed and compiled; the local sample has no duplicate chapter ordinals. Whole-library backup and restore still perform synchronous file work and may block the UI for very large collections. Reattaching original files to a retained local story remains unsupported. No database schema or hosted backend changes were made.

Working-tree changes and the simulator data container were saved under `/tmp/astral-20261022` before installation. A pre-deployment copy of the phone database, preferences and Documents is under `phone-before`; the copied SQLite database passed `PRAGMA integrity_check`. Documents copying succeeded after the phone reconnected. Initial interactive computer-use checks stopped when the Mac locked. The later simulator checks are recorded separately above; this pass does not claim tactile reader acceptance on the phone.
