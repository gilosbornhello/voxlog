"""SQLite storage for VoxLog v2 — voice events + search.

Uses WAL mode for non-blocking writes.
Supports the new voice_event schema with session, tags, modes.
"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

import aiosqlite
import structlog

from runtime.models.events import ArchiveStatus, VoiceEvent

logger = structlog.get_logger()

SCHEMA_V2 = """
CREATE TABLE IF NOT EXISTS voice_events (
    id TEXT PRIMARY KEY,
    created_at TEXT NOT NULL,
    session_id TEXT DEFAULT '',
    session_type TEXT DEFAULT 'general',
    source TEXT DEFAULT 'desktop',
    env TEXT DEFAULT 'home',
    agent TEXT DEFAULT '',
    target_app TEXT DEFAULT '',
    raw_text TEXT NOT NULL DEFAULT '',
    display_text TEXT NOT NULL DEFAULT '',
    polished_text TEXT DEFAULT '',
    audio_duration_ms INTEGER DEFAULT 0,
    stt_provider TEXT DEFAULT '',
    llm_provider TEXT DEFAULT '',
    latency_stt_ms INTEGER DEFAULT 0,
    latency_total_fast_ms INTEGER DEFAULT 0,
    latency_total_slow_ms INTEGER DEFAULT 0,
    language_mix TEXT DEFAULT 'mixed',
    tags TEXT DEFAULT '[]',
    recording_mode TEXT DEFAULT 'normal',
    archive_status TEXT DEFAULT 'pending',
    export_status TEXT DEFAULT 'pending',
    role TEXT DEFAULT 'me'
);

CREATE INDEX IF NOT EXISTS idx_ve_created ON voice_events(created_at);
CREATE INDEX IF NOT EXISTS idx_ve_agent ON voice_events(agent);
CREATE INDEX IF NOT EXISTS idx_ve_session ON voice_events(session_id);
"""

# Migration: copy old voice_log data to new voice_events table
MIGRATE_V1 = """
INSERT OR IGNORE INTO voice_events (id, created_at, source, env, agent, target_app,
    raw_text, display_text, polished_text, stt_provider, llm_provider,
    latency_total_fast_ms, role, archive_status, recording_mode)
SELECT id, created_at, 'desktop', env, COALESCE(agent, ''), target_app,
    raw_text, polished_text, polished_text, asr_provider, llm_provider,
    latency_ms, CASE WHEN target_app LIKE '%paste%' THEN 'other' ELSE 'me' END,
    'polished', 'normal'
FROM voice_log
WHERE id NOT IN (SELECT id FROM voice_events)
"""


class SQLiteStore:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self._db: aiosqlite.Connection | None = None

    async def init(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._db = await aiosqlite.connect(str(self.db_path))
        await self._db.execute("PRAGMA journal_mode=WAL")
        await self._db.execute("PRAGMA busy_timeout=5000")
        await self._db.executescript(SCHEMA_V2)

        # Migrate v1 data if old table exists
        try:
            cursor = await self._db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='voice_log'")
            if await cursor.fetchone():
                await self._db.executescript(MIGRATE_V1)
                logger.info("store.migrated_v1")
        except Exception as e:
            logger.warning("store.migrate_fail", error=str(e)[:100])

        await self._db.commit()
        count = await self.count()
        logger.info("store.init", db=str(self.db_path), records=count)

    async def close(self) -> None:
        if self._db:
            await self._db.close()
            self._db = None

    async def save_event(self, event: VoiceEvent) -> None:
        assert self._db
        import json
        await self._db.execute(
            """INSERT OR REPLACE INTO voice_events
               (id, created_at, session_id, session_type, source, env, agent, target_app,
                raw_text, display_text, polished_text, audio_duration_ms,
                stt_provider, llm_provider, latency_stt_ms, latency_total_fast_ms,
                latency_total_slow_ms, language_mix, tags, recording_mode,
                archive_status, export_status, role)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (event.id, event.created_at.isoformat(), event.session_id,
             event.session_type.value, event.source, event.env, event.agent,
             event.target_app, event.raw_text, event.display_text, event.polished_text,
             event.audio_duration_ms, event.stt_provider, event.llm_provider,
             event.latency_stt_ms, event.latency_total_fast_ms, event.latency_total_slow_ms,
             event.language_mix, json.dumps(event.tags), event.recording_mode.value,
             event.archive_status.value, event.export_status.value, event.role),
        )
        await self._db.commit()

    async def update_polish(self, event_id: str, polished_text: str) -> None:
        assert self._db
        await self._db.execute(
            "UPDATE voice_events SET polished_text=?, archive_status='polished' WHERE id=?",
            (polished_text, event_id),
        )
        await self._db.commit()

    async def delete_event(self, event_id: str) -> bool:
        assert self._db
        cursor = await self._db.execute(
            "SELECT created_at FROM voice_events WHERE id=?", (event_id,)
        )
        row = await cursor.fetchone()
        if not row:
            return False
        created = datetime.fromisoformat(row[0])
        if (datetime.now(timezone.utc) - created).total_seconds() > 120:
            return False  # 2 minute recall window
        await self._db.execute("DELETE FROM voice_events WHERE id=?", (event_id,))
        await self._db.commit()
        return True

    async def list_by_agent(self, agent: str, limit: int = 200) -> list[dict]:
        assert self._db
        cursor = await self._db.execute(
            """SELECT id, created_at, raw_text, display_text, polished_text,
                      stt_provider, llm_provider, latency_total_fast_ms,
                      target_app, role, recording_mode, agent
               FROM voice_events WHERE agent=? AND recording_mode != 'ephemeral'
               ORDER BY created_at DESC LIMIT ?""",
            (agent, limit),
        )
        return [self._row_to_dict(r) for r in await cursor.fetchall()]

    async def list_agents(self) -> list[dict]:
        assert self._db
        cursor = await self._db.execute(
            """SELECT agent, COUNT(*) as cnt, MAX(created_at) as last_ts
               FROM voice_events WHERE agent != '' AND recording_mode != 'ephemeral'
               GROUP BY agent ORDER BY last_ts DESC"""
        )
        return [{"agent": r[0], "count": r[1], "last_active": r[2]} for r in await cursor.fetchall()]

    async def search(self, query: str, limit: int = 50) -> list[dict]:
        assert self._db
        cursor = await self._db.execute(
            """SELECT id, created_at, raw_text, display_text, polished_text,
                      stt_provider, llm_provider, latency_total_fast_ms,
                      target_app, role, recording_mode, agent
               FROM voice_events
               WHERE (display_text LIKE ? OR raw_text LIKE ? OR polished_text LIKE ?)
                 AND recording_mode != 'ephemeral'
               ORDER BY created_at DESC LIMIT ?""",
            (f"%{query}%", f"%{query}%", f"%{query}%", limit),
        )
        return [self._row_to_dict(r) for r in await cursor.fetchall()]

    async def count(self) -> int:
        assert self._db
        cursor = await self._db.execute("SELECT COUNT(*) FROM voice_events")
        row = await cursor.fetchone()
        return row[0] if row else 0

    async def export_markdown(self, date_str: str) -> str:
        assert self._db
        cursor = await self._db.execute(
            """SELECT created_at, display_text, polished_text, target_app, role, agent
               FROM voice_events WHERE created_at LIKE ? AND recording_mode='normal'
               ORDER BY created_at ASC""",
            (f"{date_str}%",),
        )
        rows = await cursor.fetchall()
        if not rows:
            return f"# Voice Log: {date_str}\n\nNo records.\n"

        lines = [f"# Voice Log: {date_str}\n", f"> {len(rows)} recordings\n"]
        for ts, display, polished, app, role, agent in rows:
            time_part = ts[11:19] if len(ts) > 19 else ts
            text = polished or display
            tag = f" [{app}]" if app else ""
            role_tag = "🎤" if role == "me" else "📋"
            lines.append(f"## {time_part}{tag} {role_tag}\n\n{text}\n")
        return "\n".join(lines)

    @staticmethod
    def _row_to_dict(row) -> dict:
        return {
            "id": row[0], "created_at": row[1],
            "raw_text": row[2], "display_text": row[3], "polished_text": row[4],
            "stt_provider": row[5], "llm_provider": row[6],
            "latency_ms": row[7], "target_app": row[8],
            "role": row[9], "recording_mode": row[10], "agent": row[11],
        }
