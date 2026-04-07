# Backend API Routes

> All FastAPI route handlers under `/api/v1/`. Each router delegates to a service layer.

## Route Files

| Router | File | Prefix |
|--------|------|--------|
| comics | `backend/app/api/v1/routes/comics.py` | `/api/v1/comics` |
| fanfic | `backend/app/api/v1/routes/fanfic.py` | `/api/v1/fanfic` |
| scrape | `backend/app/api/v1/routes/scrape.py` | `/api/v1/scrape` |
| authors | `backend/app/api/v1/routes/authors.py` | `/api/v1/authors` |
| progress | `backend/app/api/v1/routes/progress.py` | `/api/v1/progress` |
| health | `backend/app/api/v1/routes/health.py` | `/api/v1/health` |
| stats | `backend/app/api/v1/routes/stats.py` | `/api/v1/stats` |

## Endpoint Catalog

### Comics

| Method | Path | Service Call | Response |
|--------|------|-------------|----------|
| GET | `/comics` | comic_service.list_comics(page, page_size, sort) | PaginatedResponse\<ComicResponse\> |
| GET | `/comics/{id}` | comic_service.get_comic(id) | ComicResponse |
| GET | `/comics/{id}/chapters/{cid}/pages` | comic_service.get_chapter_pages(id, cid) | [PageResponse] |
| PATCH | `/comics/{id}` | comic_service.update_comic(id, body) | ComicResponse |
| DELETE | `/comics/{id}` | comic_service.soft_delete_comic(id) | 204 |

### Fanfic

| Method | Path | Service Call | Response |
|--------|------|-------------|----------|
| GET | `/fanfic` | fanfic_service.list_fanfics(page, page_size, fandom, rating, completion_status, sort) | PaginatedResponse\<FanficResponse\> |
| GET | `/fanfic/{id}` | fanfic_service.get_fanfic(id) | FanficResponse |
| GET | `/fanfic/{id}/chapters/{cid}` | fanfic_service.get_chapter(id, cid) | FanficChapterResponse (with content) |
| DELETE | `/fanfic/{id}` | fanfic_service.soft_delete_fanfic(id) | 204 |

### Scrape

| Method | Path | Service Call | Response |
|--------|------|-------------|----------|
| POST | `/scrape/comic` | scrape_service.initiate_scrape(body) | ScrapeJobResponse |
| POST | `/scrape/fanfic` | scrape_service.initiate_scrape(body) | ScrapeJobResponse |
| GET | `/scrape` | scrape_service.list_jobs(page, page_size) | PaginatedResponse\<ScrapeJobResponse\> |
| GET | `/scrape/{job_id}` | scrape_service.get_job(job_id) | ScrapeJobResponse |
| POST | `/scrape/{job_id}/retry` | scrape_service.retry_job(job_id) | ScrapeJobResponse |
| POST | `/scrape/{story_id}/update` | scrape_service.delta_update(story_id) | ScrapeJobResponse |
| GET | `/scrape/{job_id}/logs` | scrape_service.get_logs(job_id) | [ScrapeLogEntry] |

### Progress

| Method | Path | Service Call | Response |
|--------|------|-------------|----------|
| PUT | `/progress/comic/{story_id}` | progress_service.upsert(comic, story_id, body) | ProgressResponse |
| PUT | `/progress/fanfic/{story_id}` | progress_service.upsert(fanfic, story_id, body) | ProgressResponse |
| GET | `/progress/{type}/{story_id}` | progress_service.get(type, story_id) | ProgressResponse |
| GET | `/progress` | progress_service.list_all(content_type) | [ProgressResponse] |

### Authors

| Method | Path | Service Call | Response |
|--------|------|-------------|----------|
| GET | `/authors/{id}` | author lookup | AuthorResponse |

### Health

| Method | Path | Response |
|--------|------|----------|
| GET | `/health` | HealthResponse { status: "ok" } |

## Relationships

| From | To | Type |
|------|----|------|
| All routes | `get_db` (dependencies.py) | FastAPI Depends — yields AsyncSession |
| comics router | comic_service | delegates all operations |
| fanfic router | fanfic_service | delegates all operations |
| scrape router | scrape_service | delegates all operations |
| progress router | progress_service | delegates all operations |
| main.py | all routers | includes with `/api/v1` prefix |
| main.py | StaticFiles | mounts at `/static` → block_volume_path |
