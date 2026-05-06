"""Test harness for the monitor service."""
import os
import sys
from unittest.mock import MagicMock

os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost:5432/test")
os.environ.setdefault("PROD", "false")

# Stub arq so monitor.main can be imported in environments without the full
# runtime stack (local dev, CI without the arq package installed).
for _mod in ("arq", "arq.jobs", "arq.connections", "asyncpg", "docker"):
    if _mod not in sys.modules:
        sys.modules[_mod] = MagicMock()
