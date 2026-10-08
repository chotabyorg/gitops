"""Bounded, serialized execution of this image's additive Alembic migrations.

The dedicated database session owns the advisory lock throughout the child
process. Losing that session kills the child. Logs contain only fixed phases.
"""

import asyncio
import contextlib
import os
import sys
import time

import asyncpg
from sqlalchemy.engine import make_url

LOCK_ID = 4348534  # Conversation-specific, database-local advisory lock.
CONNECT_TIMEOUT = 180
LOCK_TIMEOUT = 180
MIGRATION_TIMEOUT = 180


async def migrate():
    url = make_url(os.environ["DATABASE_URL"])
    if url.drivername != "postgresql+asyncpg" or not url.host or not url.database:
        raise ValueError("Invalid migration configuration")
    deadline = time.monotonic() + CONNECT_TIMEOUT
    connection = None
    while connection is None:
        try:
            connection = await asyncpg.connect(
                host=url.host,
                port=url.port or 5432,
                user=url.username,
                password=url.password,
                database=url.database,
                timeout=5,
            )
        except (OSError, asyncpg.PostgresError, TimeoutError):
            if time.monotonic() >= deadline:
                raise RuntimeError("Migration database readiness deadline exceeded") from None
            await asyncio.sleep(2)

    child = None
    try:
        await connection.execute("SELECT pg_advisory_lock($1)", LOCK_ID, timeout=LOCK_TIMEOUT)
        print("Conversation migration lock acquired", flush=True)
        child = await asyncio.create_subprocess_exec(
            "alembic", "upgrade", "head",
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        deadline = time.monotonic() + MIGRATION_TIMEOUT
        while child.returncode is None:
            await connection.execute("SELECT 1", timeout=5)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError("Migration deadline exceeded")
            try:
                await asyncio.wait_for(child.wait(), timeout=min(2, remaining))
            except TimeoutError:
                pass
        if child.returncode != 0:
            raise RuntimeError("Migration failed; application remains stopped")
        print("Conversation migration completed", flush=True)
    finally:
        if child is not None and child.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                child.kill()
            await child.wait()
        await connection.close(timeout=5)


if __name__ == "__main__":
    try:
        asyncio.run(migrate())
    except Exception:
        print("Conversation migration unsuccessful; application remains stopped", file=sys.stderr)
        sys.exit(1)
