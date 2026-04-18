from pydantic import BaseModel

FANFIC_THUMBNAIL_COUNT = 50


class RandomThumbnailResponse(BaseModel):
    path: str  # returned when count=1 or count absent


class RandomThumbnailBatchResponse(BaseModel):
    paths: list[str]  # returned when count > 1; length == min(count, 50)
