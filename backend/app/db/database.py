import logging
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.core.config import settings

logger = logging.getLogger(__name__)


class Base(DeclarativeBase):
    pass


def _build_engine():
    if settings.is_oracle:
        logger.info("Connecting to Oracle Autonomous Database (thin mode, mTLS)")
        connect_args = {
            "config_dir": str(settings.oracle_wallet_dir),
            "wallet_location": str(settings.oracle_wallet_dir),
            "wallet_password": settings.oracle_wallet_password,
        }
        engine = create_async_engine(
            settings.database_url,
            connect_args=connect_args,
            pool_size=5,
            pool_timeout=30,
            echo=False,
        )
    else:
        logger.info("Connecting to PostgreSQL database")
        engine = create_async_engine(
            settings.database_url,
            pool_size=5,
            pool_timeout=30,
            echo=False,
        )
    logger.info("SQLAlchemy async engine created | pool_size=5 pool_timeout=30")
    return engine


engine = _build_engine()
AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
