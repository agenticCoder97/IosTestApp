# Package Dependency Graph

> SPM package dependencies for the iOS app and module relationships in the backend.

## iOS SPM Packages

```mermaid
graph BT
    Core["Core<br/>(no deps)"]
    Networking["Networking<br/>(depends: Core)"]
    DesignSystem["DesignSystem<br/>(depends: Core)"]
    ComicFeature["ComicFeature<br/>(depends: Core, Networking, DesignSystem)"]
    FanficFeature["FanficFeature<br/>(depends: Core, Networking, DesignSystem)"]
    App["Astral App<br/>(depends: all 5)"]

    Core --> Networking
    Core --> DesignSystem
    Core --> ComicFeature
    Core --> FanficFeature
    Networking --> ComicFeature
    Networking --> FanficFeature
    DesignSystem --> ComicFeature
    DesignSystem --> FanficFeature
    ComicFeature --> App
    FanficFeature --> App
```

### Package Details

| Package | Path | Dependencies | Exports |
|---------|------|-------------|---------|
| Core | `Packages/Core` | none | SwiftData @Model classes, AppConfig, AstralLogger, ContentType, TimeFilter |
| Networking | `Packages/Networking` | Core | APIClient, Endpoint, CookieStore, all DTOs |
| DesignSystem | `Packages/DesignSystem` | Core | AstralColors, AstralTypography, AstralAnimations, UI components, modifiers |
| ComicFeature | `Packages/ComicFeature` | Core, Networking, DesignSystem | Comic views, viewmodels, ChapterDownloadService |
| FanficFeature | `Packages/FanficFeature` | Core, Networking, DesignSystem | Fanfic views, viewmodels |

All packages target **iOS 17+** and use **Swift 6.0** (swift-tools-version: 6.0).

## Backend Module Dependencies

```mermaid
graph BT
    core["core/<br/>config, constants"]
    db["db/<br/>database engine"]
    utils["utils/<br/>http, playwright, file, image"]
    models["models/<br/>SQLAlchemy ORM"]
    schemas["schemas/<br/>Pydantic"]
    scrapers["scrapers/<br/>base + 5 subclasses"]
    services["services/<br/>comic, fanfic, scrape, progress, stats"]
    tasks["tasks/<br/>ARQ tasks"]
    routes["api/v1/routes/"]
    main["main.py"]

    core --> db
    core --> models
    core --> schemas
    core --> scrapers
    core --> services
    db --> models
    db --> services
    db --> tasks
    models --> services
    models --> tasks
    schemas --> services
    schemas --> routes
    services --> routes
    services --> tasks
    scrapers --> tasks
    utils --> scrapers
    utils --> tasks
    routes --> main
```

## XcodeGen Configuration

Project is generated from `ios/Astral/project.yml`:
- Project name: `Astral`
- Bundle ID: `com.astral.reader`
- iOS deployment target: `17.2`
- Swift version: `6.0`
- All 5 packages declared under `packages:` with local paths
- Single target `Astral` depends on all 5 packages
