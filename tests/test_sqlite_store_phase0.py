"""Tests for Phase 0 fields in SQLite storage."""

import tempfile
from pathlib import Path

import pytest
import pytest_asyncio

from memory.sqlite_store import SQLiteStore
from runtime.models.events import OutputMode, RecordingMode, TargetRiskLevel, VoiceEvent


@pytest_asyncio.fixture
async def store():
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = Path(tmpdir) / "phase0.db"
        s = SQLiteStore(db_path)
        await s.init()
        yield s
        await s.close()


@pytest.mark.asyncio
async def test_save_event_persists_phase0_columns(store: SQLiteStore):
    event = VoiceEvent(
        session_id="session-1",
        utterance_id="utterance-1",
        target_app="Cursor",
        target_risk_level=TargetRiskLevel.MEDIUM,
        raw_text="hello world",
        display_text="hello world",
        stt_provider="whispercpp-local",
        stt_model="small-q5_1",
        output_mode=OutputMode.PREVIEW_ONLY,
        confidence=0.84,
    )

    await store.save_event(event)

    cursor = await store._db.execute(
        "SELECT utterance_id, target_risk_level, stt_model, output_mode, confidence "
        "FROM voice_events WHERE id=?",
        (event.id,),
    )
    row = await cursor.fetchone()

    assert row == (
        "utterance-1",
        "medium",
        "small-q5_1",
        "preview_only",
        0.84,
    )


@pytest.mark.asyncio
async def test_search_uses_fts_index_for_prefix_queries(store: SQLiteStore):
    event = VoiceEvent(
        session_id="session-fts",
        utterance_id="utterance-fts",
        target_app="Cursor",
        raw_text="discussed digest compiler",
        display_text="discussed digest compiler",
        polished_text="session digest compiler roadmap",
        stt_provider="whispercpp-local",
        stt_model="base.en-q5_1",
    )

    await store.save_event(event)

    results = await store.search("diges", limit=10)

    assert results
    assert results[0]["id"] == event.id


@pytest.mark.asyncio
async def test_search_empty_query_returns_recent_non_ephemeral_events(store: SQLiteStore):
    normal = VoiceEvent(
        session_id="session-normal",
        utterance_id="utterance-normal",
        target_app="Cursor",
        raw_text="normal result",
        display_text="normal result",
    )
    ephemeral = VoiceEvent(
        session_id="session-ephemeral",
        utterance_id="utterance-ephemeral",
        target_app="Terminal",
        raw_text="ephemeral result",
        display_text="ephemeral result",
        recording_mode=RecordingMode.EPHEMERAL,
    )

    await store.save_event(normal)
    await store.save_event(ephemeral)

    results = await store.search("", limit=10)

    ids = [item["id"] for item in results]
    assert normal.id in ids
    assert ephemeral.id not in ids
