"""Tests for session digest generation in the slow path."""

import tempfile
from pathlib import Path

import pytest
import pytest_asyncio

from memory.sqlite_store import SQLiteStore
from runtime.models.config import VoxLogConfig
from runtime.models.events import VoiceEvent
from runtime.slowpath.digester import DailyDigester, ProjectDigester, SessionDigester
from runtime.slowpath.enhancer import DigestEnhancer


@pytest_asyncio.fixture
async def store():
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = Path(tmpdir) / "digest.db"
        s = SQLiteStore(db_path)
        await s.init()
        yield s
        await s.close()


def test_session_digester_builds_summary_and_tags():
    digester = SessionDigester()
    event = VoiceEvent(
        session_id="sess-1",
        target_app="Cursor",
        agent="claude-code",
        raw_text="plan digest compiler roadmap for cursor refactor",
        display_text="plan digest compiler roadmap for cursor refactor",
    )

    digest = digester.build(event)

    assert digest["digest_type"] == "session_digest"
    assert digest["session_id"] == "sess-1"
    assert digest["intent"] in {"planning", "coding"}
    assert "app:cursor" in digest["suggested_tags"]


def test_daily_digester_builds_day_level_summary():
    digester = DailyDigester()
    events = [
        VoiceEvent(
            id="evt-1",
            session_id="sess-1",
            target_app="Cursor",
            agent="claude-code",
            raw_text="plan digest compiler roadmap for cursor refactor",
            display_text="plan digest compiler roadmap for cursor refactor",
        ),
        VoiceEvent(
            id="evt-2",
            session_id="sess-2",
            target_app="Terminal",
            agent="claude-code",
            raw_text="fix sqlite fts search issue for digest history",
            display_text="fix sqlite fts search issue for digest history",
        ),
    ]

    digest = digester.build(events, date_key="2026-04-04")

    assert digest["digest_type"] == "daily_digest"
    assert digest["digest_date"] == "2026-04-04"
    assert digest["source_event_id"] == "evt-2"
    assert "day:2026-04-04" in digest["suggested_tags"]
    assert digest["intent"] in {"planning", "coding", "debugging"}


def test_project_digester_builds_project_rollup():
    digester = ProjectDigester()
    events = [
        VoiceEvent(
            id="evt-1",
            session_id="sess-1",
            target_app="Cursor",
            raw_text="plan project digest rollout for cursor",
            display_text="plan project digest rollout for cursor",
        ),
        VoiceEvent(
            id="evt-2",
            session_id="sess-2",
            target_app="Cursor",
            raw_text="fix cursor policy preview regressions and digest tags",
            display_text="fix cursor policy preview regressions and digest tags",
        ),
    ]

    digest = digester.build(events, project_key="cursor")

    assert digest["digest_type"] == "project_digest"
    assert digest["project_key"] == "cursor"
    assert digest["source_event_id"] == "evt-2"
    assert "project:cursor" in digest["suggested_tags"]
    assert digest["intent"] in {"planning", "debugging"}


@pytest.mark.asyncio
async def test_digest_enhancer_falls_back_without_provider_keys():
    enhancer = DigestEnhancer()
    config = VoxLogConfig(
        openai_key="",
        dashscope_key_us="",
        dashscope_key_cn="",
        siliconflow_key="",
    )
    config.profiles["home"].llm_main = "openai-gpt"
    digest = await enhancer.enhance(
        {
            "digest_type": "session_digest",
            "session_id": "sess-1",
            "summary": "heuristic summary",
            "intent": "planning",
            "suggested_tags": ["app:cursor"],
            "mentioned_entities": ["cursor"],
        },
        "plan digest rollout",
        config,
    )

    assert digest["enhanced"] is False
    assert digest["enhancer_provider"] == "heuristic"
    assert digest["summary"] == "heuristic summary"


@pytest.mark.asyncio
async def test_store_upserts_session_digest(store: SQLiteStore):
    await store.upsert_session_digest(
        session_id="sess-digest",
        source_event_id="event-1",
        summary="first summary",
        intent="planning",
        suggested_tags=["app:cursor"],
        mentioned_entities=["cursor"],
    )

    await store.upsert_session_digest(
        session_id="sess-digest",
        source_event_id="event-2",
        summary="updated summary",
        intent="coding",
        suggested_tags=["app:cursor", "agent:claude-code"],
        mentioned_entities=["cursor", "claude"],
        enhanced=True,
        enhancer_provider="openai",
    )

    digest = await store.get_session_digest("sess-digest")

    assert digest is not None
    assert digest["source_event_id"] == "event-2"
    assert digest["summary"] == "updated summary"
    assert "agent:claude-code" in digest["suggested_tags"]
    assert digest["enhanced"] is True
    assert digest["enhancer_provider"] == "openai"


@pytest.mark.asyncio
async def test_store_upserts_daily_digest(store: SQLiteStore):
    await store.upsert_daily_digest(
        digest_date="2026-04-04",
        source_event_id="event-1",
        summary="first daily summary",
        intent="planning",
        suggested_tags=["day:2026-04-04"],
        mentioned_entities=["cursor"],
    )

    await store.upsert_daily_digest(
        digest_date="2026-04-04",
        source_event_id="event-2",
        summary="updated daily summary",
        intent="coding",
        suggested_tags=["day:2026-04-04", "app:cursor"],
        mentioned_entities=["cursor", "digest"],
        enhanced=True,
        enhancer_provider="qwen",
    )

    digest = await store.get_daily_digest("2026-04-04")

    assert digest is not None
    assert digest["digest_type"] == "daily_digest"
    assert digest["digest_date"] == "2026-04-04"
    assert digest["source_event_id"] == "event-2"
    assert digest["summary"] == "updated daily summary"
    assert digest["enhanced"] is True
    assert digest["enhancer_provider"] == "qwen"


@pytest.mark.asyncio
async def test_store_upserts_project_digest(store: SQLiteStore):
    await store.upsert_project_digest(
        project_key="cursor",
        source_event_id="event-1",
        summary="first project summary",
        intent="planning",
        suggested_tags=["project:cursor"],
        mentioned_entities=["cursor"],
    )

    await store.upsert_project_digest(
        project_key="cursor",
        source_event_id="event-2",
        summary="updated project summary",
        intent="debugging",
        suggested_tags=["project:cursor", "entity:digest"],
        mentioned_entities=["cursor", "digest"],
        enhanced=True,
        enhancer_provider="ollama",
    )

    digest = await store.get_project_digest("cursor")

    assert digest is not None
    assert digest["digest_type"] == "project_digest"
    assert digest["project_key"] == "cursor"
    assert digest["source_event_id"] == "event-2"
    assert digest["summary"] == "updated project summary"
    assert digest["enhanced"] is True
    assert digest["enhancer_provider"] == "ollama"
