"""Test harness for the monitor service."""
import os

os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost:5432/test")
os.environ.setdefault("PROD", "false")
