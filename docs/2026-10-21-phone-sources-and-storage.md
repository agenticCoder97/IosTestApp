# Phone sources and comic storage

21 October 2026. Follow-up to the rebuild implementation. Verification limitations below apply to this implementation.

## Scope

The user clarified that the default is **two comics saved offline**, not 2 GB. The count is adjustable in Settings. The user subsequently excluded NSFW source testing; no further live checks of those sources are part of acceptance. Previously implemented source-adapter code remains unverified where noted; it must not be advertised as live-tested support.

The remaining live acceptance focuses on FFNet, MangaDex and storage controls. No backend, proxy or archive service is started or required by these import paths.

## Storage behavior

- Settings → Offline comics defaults to 2 and can be changed from 1–100 immediately. A comic with any saved chapter occupies one slot. Metadata-only library entries do not occupy slots.
- Comic storage budget defaults to 5 GB and is independently adjustable from 1–100 GB. The slot count alone would not bound the size of a very large series.
- Downloads and folder imports share reservations for slots and bytes. Concurrent jobs cannot each take the last slot. Existing copies remain intact on rejection/cancellation/failure.
- Lowering a limit never automatically removes saved content. Storage shows an above-limit message and blocks new offline comics until the user frees space or raises the limit.
- Bulk downloading stops when the storage budget or disk space runs out rather than trying every remaining chapter. Successfully saved chapters remain available.
- Storage measures actual comic folder sizes; older copies without recorded byte counts are measured before further downloads. Page downloads use a transport without a second implicit disk cache. Covers retain their separate bounded 200 MB cache.
- Remove saved pages clears chapter paths/download flags/byte counts and removes the files, while retaining story metadata, favourites, bookmarks and reading position. An active import/download must be cancelled before removal/deletion.
- Saved content removal is distinct from deleting a story. Existing transactional removal/recovery behavior is retained.

## FFNet acquisition

- Import uses the phone's own WKWebView session and normal chapter navigation. It supports desktop and mobile chapter layouts and does not send cookies to an Astral server.
- Chapter count and identity are checked; extraction is paced and cancellable. A full validated work is committed to the existing local database/text-file reader.
- A temporary bounded acquisition checkpoint permits retry after source verification. A checkpoint is reused only for a recent, matching work/count/first chapter, and is removed after successful import. Partial text is not exposed as a completed library entry.
- Verification/login/rate-limit failures remain source limitations. The app surfaces the source page and retains saved copies. There is no claim of Cloudflare immunity.
- Update, retry and restoring removed text route back to the device importer. FFNet does not use the legacy server chapter/download fallback.

## Verification

- Isolated checks use the actual production policy/removal code and SwiftData models with temporary filesystem roots. Passed: concurrent third-comic rejection; shared reservations for one comic; lowering a limit during a pending save; byte budget rejection; active-operation removal guard; file removal; metadata/bookmark/progress retention; freed-slot reuse; repeat removal.
- Simulator Settings showed the default 2-comic / 5-GB controls. Lowering the count to 1 produced “2 / 1” and retained both copies. Removing the replaceable MangaDex saved pages produced “1 / 1”, disabled that comic's removal button and reduced Documents content from 8.4 MB to 797 KB. The count was restored to 2.
- Database inspection after removal retained The Ghostly Doctor and its chapter-2/page-11 reading position. Resaving chapter 0 through Reader → More → Save chapter completed: four files totaling 7,599,096 bytes, one completed download Activity job, and Storage returned to 2 / 2 with 7.6 MB for that comic. The original chapter-2/page-11 position and progress value were restored through the reader and verified in SQLite.
- The isolated WebKit parser checks passed gallery JSON, Madara chapter ordering, reader image JSON, FFNet desktop parsing with duplicate chapter dropdowns, and extraction of 68 chapter links from live source HTML. These are parser checks, not complete live provider acceptance. NSFW live checks were stopped at the user's instruction.
- FFNet live testing used Harry Potter and the Methods of Rationality (122 chapters). It read desktop/mobile layouts, reused checkpoints from 11 → 21 → 31 chapters, and preserved partial acquisition without creating an incomplete library entry. A readiness bug was fixed: valid chapter DOM now permits progress without waiting for unrelated page resources. The final attempt encountered an actual Cloudflare “Performing security verification” page at chapter 32, then surfaced the verification error and retained a 31-chapter checkpoint. Complete FFNet import/update/reader acceptance is still blocked by source verification; it is not claimed as passed. The checkpoint expires after one hour, so later attempts may restart.
- Final Debug and Release simulator builds passed for iPhone 17 Pro / iOS 26.4, including source readiness and download-error feedback fixes. Logs: `/tmp/astral-phone-build.log` and `/tmp/astral-phone-release.log`. The only warning is skipped App Intents metadata extraction (no framework dependency). The Debug app was installed and launched. `git diff --check` passed. These checks used the on-device paths with no companion configured; they do not replace physical-device or radio-off acceptance.

Do not interpret parser/build success as proof that a protected provider will always permit acquisition. Physical-device memory, large-library performance and the previously documented gesture/accessibility matrix remain separate acceptance work.

## Delivery boundary

The local database and saved text/pages remain authoritative. AO3, FFNet and MangaDex
paths do not require the Astral backend. Source websites still require Internet access
for new acquisition, and can require login or verification. Offline reading uses saved
files. FFNet is implemented and partially exercised, with complete live acquisition
blocked as recorded above. Other provider adapters remain unverified because their
live testing was excluded by the user. No protected-source bypass is implemented.

No repository test suite was added. Initial SQLite/Documents and working-tree changes
were retained under `/tmp/astral-phone-sources-20261021`. This report records the implementation and its verification boundary.
