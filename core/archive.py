"""SQLite archive for voice history.

All voice inputs are permanently stored locally. WAL mode for non-blocking writes.
"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import aiosqlite
import structlog

from core.models import ArchiveRecord, VoiceResult

logger = structlog.get_logger()

SCHEMA = """
CREATE TABLE IF NOT EXISTS voice_log (
    id TEXT PRIMARY KEY,
    raw_text TEXT NOT NULL,
    polished_text TEXT NOT NULL,
    asr_provider TEXT NOT NULL,
    llm_provider TEXT,
    polished INTEGER NOT NULL DEFAULT 1,
    duration_seconds REAL NOT NULL DEFAULT 0.0,
    latency_ms INTEGER NOT NULL DEFAULT 0,
    target_app TEXT NOT NULL DEFAULT '',
    env TEXT NOT NULL DEFAULT 'home',
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_voice_log_created_at ON voice_log(created_at);
"""


class Archive:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self._db: aiosqlite.Connection | None = None

    async def init(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._db = await aiosqlite.connect(str(self.db_path))
        await self._db.execute("PRAGMA journal_mode=WAL")
        await self._db.execute("PRAGMA busy_timeout=5000")
        await self._db.executescript(SCHEMA)
        await self._db.commit()
        logger.info("archive.initialized", db=str(self.db_path))

    async def close(self) -> None:
        if self._db:
            await self._db.close()
            self._db = None

    async def save(self, result: VoiceResult) -> None:
        if not self._db:
            raise RuntimeError("Archive not initialized")
        await self._db.execute(
            """INSERT INTO voice_log
               (id, raw_text, polished_text, asr_provider, llm_provider,
                polished, duration_seconds, latency_ms, target_app, env, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                result.id,
                result.raw_text,
                result.polished_text,
                result.asr_provider.value,
                result.llm_provider.value if result.llm_provider else None,
                1 if result.polished else 0,
                result.duration_seconds,
                result.latency_ms,
                result.target_app,
                result.env.value,
                result.created_at.isoformat(),
            ),
        )
        await self._db.commit()
        logger.info("archive.saved", id=result.id, text_len=len(result.polished_text))

    async def search(self, query: str, limit: int = 50) -> list[ArchiveRecord]:
        if not self._db:
            raise RuntimeError("Archive not initialized")
        cursor = await self._db.execute(
            """SELECT id, raw_text, polished_text, asr_provider, llm_provider,
                      polished, duration_seconds, latency_ms, target_app, env, created_at
               FROM voice_log
               WHERE polished_text LIKE ? OR raw_text LIKE ?
               ORDER BY created_at DESC LIMIT ?""",
            (f"%{query}%", f"%{query}%", limit),
        )
        rows = await cursor.fetchall()
        return [self._row_to_record(row) for row in rows]

    async def list_by_date(self, date_str: str, limit: int = 200) -> list[ArchiveRecord]:
        """List records for a given date (YYYY-MM-DD)."""
        if not self._db:
            raise RuntimeError("Archive not initialized")
        cursor = await self._db.execute(
            """SELECT id, raw_text, polished_text, asr_provider, llm_provider,
                      polished, duration_seconds, latency_ms, target_app, env, created_at
               FROM voice_log
               WHERE created_at LIKE ?
               ORDER BY created_at ASC LIMIT ?""",
            (f"{date_str}%", limit),
        )
        rows = await cursor.fetchall()
        return [self._row_to_record(row) for row in rows]

    async def count(self) -> int:
        if not self._db:
            raise RuntimeError("Archive not initialized")
        cursor = await self._db.execute("SELECT COUNT(*) FROM voice_log")
        row = await cursor.fetchone()
        return row[0] if row else 0

    async def export_markdown(self, date_str: str) -> str:
        """Export a day's voice log as Markdown for Obsidian."""
        records = await self.list_by_date(date_str)
        if not records:
            return f"# Voice Log: {date_str}\n\nNo records.\n"

        lines = [f"# Voice Log: {date_str}\n"]
        for r in records:
            ts = r.created_at.strftime("%H:%M:%S")
            app_tag = f" [{r.target_app}]" if r.target_app else ""
            polished_tag = "" if r.polished else " (raw)"
            lines.append(f"## {ts}{app_tag}{polished_tag}\n")
            lines.append(f"{r.polished_text}\n")
        return "\n".join(lines)

    @staticmethod
    def _row_to_record(row: tuple) -> ArchiveRecord:
        return ArchiveRecord(
            id=row[0],
            raw_text=row[1],
            polished_text=row[2],
            asr_provider=row[3],
            llm_provider=row[4],
            polished=bool(row[5]),
            duration_seconds=row[6],
            latency_ms=row[7],
            target_app=row[8],
            env=row[9],
            created_at=datetime.fromisoformat(row[10]),
        )
