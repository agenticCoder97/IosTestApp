from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.core.config import settings


class Base(DeclarativeBase):
    pass


def _build_engine():
    if settings.is_oracle:
        connect_args = {
            "config_dir": str(settings.oracle_wallet_dir),
            "wallet_location": str(settings.oracle_wallet_dir),
            "wallet_password": settings.oracle_wallet_password,
        }
        return create_async_engine(
            settings.database_url,
            connect_args=connect_args,
            pool_size=5,
            pool_timeout=30,
            echo=False,
        )
    else:
        return create_async_engine(
            settings.database_url,
            pool_size=5,
            pool_timeout=30,
            echo=False,
        )


engine = _build_engine()
AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
