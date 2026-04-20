"""Centralized TTLs for the response cache. Avoids magic numbers at call sites.

All values are in seconds. Bump these to tune freshness vs. cache hit-rate
without grepping through service layers.
"""


class CacheTTL:
    LIST = 300              # 5 min — list endpoints + single-resource detail blobs
    CHAPTER_PAGES = 86400   # 24 h — comic chapter image manifests (effectively immutable)
    PROGRESS = 120          # 2 min — reading progress aggregate
