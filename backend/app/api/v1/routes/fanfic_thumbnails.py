import random
from typing import Union
from fastapi import APIRouter, Query
from app.schemas.fanfic_thumbnail import (
    RandomThumbnailResponse,
    RandomThumbnailBatchResponse,
    FANFIC_THUMBNAIL_COUNT,
)

router = APIRouter(prefix="/fanfic-thumbnails", tags=["fanfic-thumbnails"])


@router.get("/random")
async def random_fanfic_thumbnail(
    count: int = Query(default=1, ge=1, le=FANFIC_THUMBNAIL_COUNT),
) -> Union[RandomThumbnailResponse, RandomThumbnailBatchResponse]:
    if count == 1:
        n = random.randint(1, FANFIC_THUMBNAIL_COUNT)
        return RandomThumbnailResponse(path=f"fanfic-thumbnails/{n}.jpg")
    paths = [
        f"fanfic-thumbnails/{random.randint(1, FANFIC_THUMBNAIL_COUNT)}.jpg"
        for _ in range(count)
    ]
    return RandomThumbnailBatchResponse(paths=paths)
