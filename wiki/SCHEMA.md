# Wiki Schema — Operating Rules

This file defines how the Astral knowledge graph wiki is structured and maintained. Any LLM agent or human contributor must follow these rules.

## Inspired By

[Andrej Karpathy's LLM Knowledge Bases](https://x.com/karpathy/status/2039805659525644595) — compile knowledge once into a structured wiki that LLMs read and update incrementally, rather than re-discovering it from raw source files on every query.

## Folder Structure

```
wiki/
  SCHEMA.md                     # This file — rules for maintaining the wiki
  INDEX.md                      # Master index of all entities and pages

  architecture/                 # System-level diagrams and data flow
    overview.md                 # Deployment topology, tech stack
    data-flow.md                # End-to-end data flow (scrape → store → display)
    package-dependency-graph.md # SPM + backend module dependency graph

  ios/                          # One page per iOS package/layer
    app-layer.md
    core-package.md
    networking-package.md
    design-system-package.md
    comic-feature.md
    fanfic-feature.md

  backend/                      # One page per backend module
    api-routes.md
    services.md
    orm-models.md
    scrapers.md
    tasks.md
    infrastructure.md

  entities/                     # Cross-cutting entity pages (traces one entity across all layers)
    comic.md
    fanfic.md
    author.md
    scrape-job.md
    reading-progress.md

  concepts/                     # End-to-end flows that cross module boundaries
    cookie-harvest-flow.md
    scrape-pipeline.md
    offline-mode.md
    soft-delete-pattern.md

  known-issues/                 # Persistent bugs and architectural gaps
    empty-tables.md
    scraper-bugs.md
```

## Page Template

Every wiki page must follow this structure:

```markdown
# Page Title

> One-sentence summary of what this page covers.

## Entities

| Name | Type | File | Description |
|------|------|------|-------------|
| ...  | ...  | ...  | ...         |

## Relationships

| From | To | Type | Description |
|------|-----|------|-------------|
| ...  | ... | ...  | ...         |

## Diagram

(Mermaid diagram — renders in GitHub markdown)

## File References

- `path/to/file.swift:42` — description of what's at that line
```

Not every section is required — use what's relevant. Entity pages (in `entities/`) must have entries for every layer the entity appears in.

## Citation Rules

- Always reference actual file paths relative to the repo root.
- Use `file.swift:42` format when referencing a specific line.
- Never cite a file you haven't verified exists.
- When a wiki page claims a function or type exists, it must be currently present in the codebase.

## Update Workflow

When source code changes, update the wiki:

1. **New model/type added** → Update the relevant layer page + entity page + INDEX.md
2. **New scraper added** → Update `backend/scrapers.md` + `entities/scrape-job.md` + `concepts/scrape-pipeline.md`
3. **New endpoint added** → Update `backend/api-routes.md` + `ios/networking-package.md` + relevant entity page
4. **New view added** → Update the relevant feature page (`ios/comic-feature.md` or `ios/fanfic-feature.md`)
5. **Known issue resolved** → Remove or mark as resolved in `known-issues/`
6. **Architecture change** → Update `architecture/overview.md` and affected pages

## Conventions

- Keep pages factual, not aspirational. Document what IS, not what SHOULD BE.
- Mermaid diagrams use `graph TB` (top-bottom) for hierarchies, `graph LR` (left-right) for flows.
- Entity relationship diagrams use `erDiagram`.
- Use concise descriptions — this is a reference, not a tutorial.
- Do not duplicate content across pages. Link to the authoritative page instead.
