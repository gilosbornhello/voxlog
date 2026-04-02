"""Tests for core.exporter — multi-format voice log export."""

import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import sqlite3

from core.exporter import export_csv, export_json, export_plaintext, export_weekly_summary


def _setup_db(records: list[tuple]) -> Path:
    """Create a test DB with records: (id, created_at, raw, polished, asr, llm, polished_bool, dur, lat, app, env)"""
    db_path = Path(tempfile.mkdtemp()) / "test.db"
    db = sqlite3.connect(str(db_path))
    db.execute("""CREATE TABLE voice_log (
        id TEXT, created_at TEXT, raw_text TEXT, polished_text TEXT,
        asr_provider TEXT, llm_provider TEXT, polished INTEGER,
        duration_seconds REAL, latency_ms INTEGER, target_app TEXT, env TEXT
    )""")
    for r in records:
        db.execute("INSERT INTO voice_log VALUES (?,?,?,?,?,?,?,?,?,?,?)", r)
    db.commit()
    db.close()
    return db_path


def _sample_records():
    return [
        ("id1", "2026-04-01T10:00:00Z", "raw one", "Polished one.", "qwen", "openai_gpt", 1, 3.0, 800, "Claude Code", "home"),
        ("id2", "2026-04-01T14:30:00Z", "raw two", "Polished two.", "openai_whisper", "qwen_turbo", 1, 5.0, 1200, "Terminal", "home"),
    ]


class TestExportJSON:
    def test_basic(self):
        db = _setup_db(_sample_records())
        result = json.loads(export_json(db, "2026-04-01"))
        assert result["count"] == 2
        assert result["records"][0]["polished_text"] == "Polished one."

    def test_empty_date(self):
        db = _setup_db(_sample_records())
        result = json.loads(export_json(db, "1999-01-01"))
        assert result["count"] == 0


class TestExportCSV:
    def test_basic(self):
        db = _setup_db(_sample_records())
        csv_str = export_csv(db, "2026-04-01")
        assert "time,text,raw_text,asr" in csv_str
        assert "Polished one." in csv_str
        lines = csv_str.strip().split("\n")
        assert len(lines) == 3  # header + 2 records


class TestExportPlaintext:
    def test_basic(self):
        db = _setup_db(_sample_records())
        text = export_plaintext(db, "2026-04-01")
        assert "Polished one." in text
        assert "[10:00:00]" in text

    def test_empty(self):
        db = _setup_db([])
        text = export_plaintext(db, "2026-04-01")
        assert "No voice records" in text


class TestWeeklySummary:
    def test_basic(self):
        records = _sample_records() + [
            ("id3", "2026-03-31T09:00:00Z", "raw three", "Day before.", "qwen", None, 1, 2.0, 500, "", "home"),
        ]
        db = _setup_db(records)
        md = export_weekly_summary(db, "2026-04-01")
        assert "Weekly Voice Log" in md
        assert "2026-04-01" in md
        assert "Polished one." in md
