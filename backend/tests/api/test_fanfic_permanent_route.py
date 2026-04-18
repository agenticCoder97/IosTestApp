import uuid
import pytest
from tests.conftest import make_fanfic


@pytest.mark.asyncio
async def test_permanent_delete_fanfic_route_returns_204(client, db_session):
    fanfic = make_fanfic()
    db_session.add(fanfic)
    await db_session.commit()
    fanfic_id = fanfic.id

    response = await client.delete(f"/fanfic/{fanfic_id}/permanent")
    assert response.status_code == 204

    # Verify row is gone
    from sqlalchemy import select
    from app.models.fanfic import Fanfic

    result = await db_session.execute(select(Fanfic).where(Fanfic.id == fanfic_id))
    assert result.scalar_one_or_none() is None


@pytest.mark.asyncio
async def test_permanent_delete_fanfic_route_unknown_id_returns_204(client):
    random_id = uuid.uuid4()
    response = await client.delete(f"/fanfic/{random_id}/permanent")
    assert response.status_code == 204  # Idempotent
