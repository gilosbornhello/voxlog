"""Tests for the minimal AI Mate Memory digest export sink."""

from __future__ import annotations

import json
from pathlib import Path

from integrations.ai_mate_memory import AIMateMemorySink


def test_ai_mate_memory_sink_exports_project_digest(tmp_path: Path):
    sink = AIMateMemorySink(tmp_path)
    result = sink.export_digest(
        scope="project",
        markdown="# project_digest\n\nCursor work",
        project_key="cursor",
    )
    assert result.bytes_written > 0
    payload = json.loads(Path(result.record_path).read_text(encoding="utf-8"))
    assert payload["scope"] == "project"
    assert payload["project_key"] == "cursor"
    assert "Cursor work" in payload["content_markdown"]
