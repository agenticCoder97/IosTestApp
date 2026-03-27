from typing import Generic, TypeVar
from pydantic import BaseModel, ConfigDict
import uuid
from datetime import datetime

T = TypeVar("T")


class PaginatedResponse(BaseModel, Generic[T]):
    model_config = ConfigDict(populate_by_name=True)
    items: list[T]
    total: int
    page: int
    page_size: int
    total_pages: int
    has_next: bool


class AuthorResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: uuid.UUID
    name: str


class TagResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: uuid.UUID
    name: str
    tag_type: str


class HealthResponse(BaseModel):
    status: str


class CookieDTO(BaseModel):
    name: str
    value: str
    domain: str
