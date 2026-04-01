"""Tests for core.archive — SQLite storage, search, export."""

import tempfile
from datetime import datetime, timezone
from pathlib import Path

import pytest

from core.archive import Archive
from core.models import ASRProvider, Environment, LLMProvider, VoiceResult


def _make_result(**kwargs) -> VoiceResult:
    defaults = dict(
        raw_text="test raw",
        polished_text="test polished",
        asr_provider=ASRProvider.QWEN,
        llm_provider=LLMProvider.QWEN_TURBO,
        polished=True,
        duration_seconds=3.5,
        latency_ms=800,
        target_app="Claude Code",
        env=Environment.HOME,
    )
    defaults.update(kwargs)
    return VoiceResult(**defaults)


@pytest.fixture
async def archive():
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = Path(tmpdir) / "test.db"
        a = Archive(db_path)
        await a.init()
        yield a
        await a.close()


class TestArchive:
    async def test_save_and_count(self, archive: Archive):
        await archive.save(_make_result())
        assert await archive.count() == 1

    async def test_save_multiple(self, archive: Archive):
        for i in range(5):
            await archive.save(_make_result(raw_text=f"test {i}"))
        assert await archive.count() == 5

    async def test_search_by_text(self, archive: Archive):
        await archive.save(_make_result(polished_text="把 pricing 放到 hero 下面"))
        await archive.save(_make_result(polished_text="修改 auth 逻辑"))
        results = await archive.search("pricing")
        assert len(results) == 1
        assert "pricing" in results[0].polished_text

    async def test_search_empty_query(self, archive: Archive):
        await archive.save(_make_result())
        results = await archive.search("")
        assert len(results) == 1  # LIKE '%%' matches all

    async def test_list_by_date(self, archive: Archive):
        r = _make_result()
        await archive.save(r)
        date_str = r.created_at.strftime("%Y-%m-%d")
        results = await archive.list_by_date(date_str)
        assert len(results) == 1

    async def test_list_by_date_no_match(self, archive: Archive):
        await archive.save(_make_result())
        results = await archive.list_by_date("1999-01-01")
        assert len(results) == 0

    async def test_export_markdown(self, archive: Archive):
        r = _make_result(polished_text="Hello VoxLog")
        await archive.save(r)
        date_str = r.created_at.strftime("%Y-%m-%d")
        md = await archive.export_markdown(date_str)
        assert "Voice Log" in md
        assert "Hello VoxLog" in md

    async def test_export_empty_date(self, archive: Archive):
        md = await archive.export_markdown("1999-01-01")
        assert "No records" in md

    async def test_db_auto_create(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            db_path = Path(tmpdir) / "subdir" / "test.db"
            a = Archive(db_path)
            await a.init()
            assert db_path.exists()
            await a.close()

    async def test_not_initialized_raises(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            a = Archive(Path(tmpdir) / "test.db")
            with pytest.raises(RuntimeError, match="not initialized"):
                await a.save(_make_result())
