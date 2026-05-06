import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';

export const options = {
  stages: [
    { duration: '1m',  target: 5   },  // warm-up
    { duration: '2m',  target: 5   },  // baseline hold
    { duration: '2m',  target: 25  },  // ramp
    { duration: '2m',  target: 25  },  // hold
    { duration: '2m',  target: 50  },  // ramp
    { duration: '2m',  target: 50  },  // hold
    { duration: '2m',  target: 100 },  // push
    { duration: '2m',  target: 100 },  // hold
    { duration: '1m',  target: 0   },  // cool-down
  ],
  thresholds: {
    http_req_duration:                          ['p(95)<500', 'p(95)<2000'],
    http_req_failed:                            ['rate<0.05'],
    'http_req_duration{name:progress_write}':   ['p(95)<1000'],
  },
};

export function setup() {
  const listRes = http.get(`${BASE_URL}/api/v1/comics?page=1&page_size=20`);
  check(listRes, { 'setup: comics list 200': r => r.status === 200 });

  const body = listRes.json();
  const comics = (body.items || []).filter(c => c.total_chapters > 0);

  if (comics.length === 0) {
    throw new Error('setup: no comics found — seed the database before running');
  }

  // Fetch up to 5 comic details to collect (comicId, chapterId, chapterNumber) tuples.
  // list_comics omits chapters (include_chapters=False in comic_service.py:110),
  // so we need the individual GET to get chapter UUIDs.
  const targets = [];
  for (const comic of comics.slice(0, 5)) {
    const detailRes = http.get(`${BASE_URL}/api/v1/comics/${comic.id}`);
    if (detailRes.status !== 200) continue;
    const detail = detailRes.json();
    const chapters = (detail.chapters || []).filter(ch => ch.scrape_status === 'scraped');
    for (const ch of chapters.slice(0, 3)) {
      targets.push({
        comicId: comic.id,
        chapterId: ch.id,
        chapterNumber: Math.round(ch.chapter_number),
      });
    }
  }

  if (targets.length === 0) {
    throw new Error('setup: no scraped chapters found — run a scrape job first');
  }

  return { targets };
}

export default function (data) {
  const target = data.targets[Math.floor(Math.random() * data.targets.length)];
  const headers = { 'Content-Type': 'application/json' };

  // 1 — list comics
  const listRes = http.get(
    `${BASE_URL}/api/v1/comics?page=1&page_size=20`,
    { tags: { name: 'comics_list' } },
  );
  check(listRes, { 'comics_list 200': r => r.status === 200 });
  sleep(0.5 + Math.random() * 0.5);

  // 2 — comic detail
  const detailRes = http.get(
    `${BASE_URL}/api/v1/comics/${target.comicId}`,
    { tags: { name: 'comic_detail' } },
  );
  check(detailRes, { 'comic_detail 200': r => r.status === 200 });
  sleep(0.5 + Math.random() * 0.5);

  // 3 — chapter pages
  const pagesRes = http.get(
    `${BASE_URL}/api/v1/comics/${target.comicId}/chapters/${target.chapterId}/pages`,
    { tags: { name: 'chapter_pages' } },
  );
  check(pagesRes, { 'chapter_pages 200': r => r.status === 200 });
  sleep(0.5 + Math.random() * 0.5);

  // 4 — write progress (ComicProgressRequest requires last_chapter_number: int)
  const progressRes = http.put(
    `${BASE_URL}/api/v1/progress/comic/${target.comicId}`,
    JSON.stringify({ last_chapter_number: target.chapterNumber }),
    { headers, tags: { name: 'progress_write' } },
  );
  check(progressRes, { 'progress_write 200': r => r.status === 200 });
  sleep(0.5 + Math.random() * 0.5);

  // 5 — stats
  const statsRes = http.get(
    `${BASE_URL}/api/v1/stats`,
    { tags: { name: 'stats' } },
  );
  check(statsRes, { 'stats 200': r => r.status === 200 });
  sleep(0.5 + Math.random() * 0.5);
}
