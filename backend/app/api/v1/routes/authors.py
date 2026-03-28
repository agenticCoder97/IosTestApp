import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.dependencies import get_db
from app.schemas.shared import AuthorResponse
from app.services import comic_service, fanfic_service

router = APIRouter(prefix="/authors", tags=["authors"])


@router.get("/{author_id}", response_model=AuthorResponse)
async def get_author(author_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    from app.models.author import Author
    from sqlalchemy import select
    result = await db.execute(
        select(Author).where(Author.id == author_id, Author.deleted_at.is_(None))
    )
    author = result.scalar_one_or_none()
    if not author:
        raise HTTPException(status_code=404, detail="Author not found")
    return AuthorResponse(id=author.id, name=author.name)
