"""Bounded DB readiness + a database-scoped lock around the image's Alembic CLI.

Never print connection settings or raw exceptions. The lock connection is
monitored while Alembic runs; losing it terminates the migration child.
"""

import asyncio
import contextlib
import sys
import time

import asyncpg
from sqlalchemy.engine import make_url

from app.core.config import Settings


LOCK_ID = 4348524  # CRM-specific, database-local advisory lock.
CONNECT_TIMEOUT = 180
LOCK_TIMEOUT = 180
MIGRATION_TIMEOUT = 180


async def migrate():
    url = make_url(Settings().database_url.get_secret_value())
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
                raise RuntimeError("CRM database readiness deadline exceeded") from None
            await asyncio.sleep(2)

    child = None
    try:
        await connection.execute(
            "SELECT pg_advisory_lock($1)", LOCK_ID, timeout=LOCK_TIMEOUT
        )
        print("CRM migration lock acquired", flush=True)
        child = await asyncio.create_subprocess_exec(
            "alembic", "upgrade", "head",
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        deadline = time.monotonic() + MIGRATION_TIMEOUT
        while child.returncode is None:
            # Any lost lock/session prevents this initContainer from succeeding.
            await connection.execute("SELECT 1", timeout=5)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError("CRM migration deadline exceeded")
            try:
                await asyncio.wait_for(child.wait(), timeout=min(2, remaining))
            except TimeoutError:
                pass
        if child.returncode != 0:
            raise RuntimeError("CRM migration failed; application remains stopped")
        print("CRM migration completed", flush=True)
    finally:
        if child is not None and child.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                child.kill()
            await child.wait()
        # Closing the session releases the advisory lock, including on failure.
        await connection.close(timeout=5)


if __name__ == "__main__":
    try:
        asyncio.run(migrate())
    except Exception:
        # Driver/Alembic errors may include a DSN or SQL. Keep operator logs safe.
        print("CRM migration unsuccessful; check database readiness and reviewed migration", file=sys.stderr)
        sys.exit(1)
