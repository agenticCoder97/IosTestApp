import uuid
import pytest
from tests.conftest import make_comic


@pytest.mark.asyncio
async def test_permanent_delete_comic_route_returns_204(client, db_session):
    comic = make_comic()
    db_session.add(comic)
    await db_session.commit()
    comic_id = comic.id

    response = await client.delete(f"/comics/{comic_id}/permanent")
    assert response.status_code == 204

    # Verify row is gone
    from sqlalchemy import select
    from app.models.comic import Comic

    result = await db_session.execute(select(Comic).where(Comic.id == comic_id))
    assert result.scalar_one_or_none() is None


@pytest.mark.asyncio
async def test_permanent_delete_comic_route_unknown_id_returns_204(client):
    random_id = uuid.uuid4()
    response = await client.delete(f"/comics/{random_id}/permanent")
    assert response.status_code == 204  # Idempotent
