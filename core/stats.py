"""Usage statistics and cost tracking for VoxLog.

Tracks API calls and estimates costs to prevent bill surprise.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class UsageStats:
    total_recordings: int
    total_duration_min: float
    today_recordings: int
    today_duration_min: float
    asr_breakdown: dict[str, int]
    llm_breakdown: dict[str, int]
    avg_latency_ms: float
    estimated_monthly_cost_cny: float


def calculate_stats(db_path: Path) -> UsageStats:
    if not db_path.exists():
        return UsageStats(0, 0, 0, 0, {}, {}, 0, 0)

    db = sqlite3.connect(str(db_path))
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    total = db.execute("SELECT COUNT(*) FROM voice_log").fetchone()[0]
    total_dur = db.execute("SELECT COALESCE(SUM(duration_seconds), 0) FROM voice_log").fetchone()[0]
    today_count = db.execute(
        "SELECT COUNT(*) FROM voice_log WHERE created_at LIKE ?", (f"{today}%",)
    ).fetchone()[0]
    today_dur = db.execute(
        "SELECT COALESCE(SUM(duration_seconds), 0) FROM voice_log WHERE created_at LIKE ?",
        (f"{today}%",),
    ).fetchone()[0]
    avg_lat = db.execute("SELECT COALESCE(AVG(latency_ms), 0) FROM voice_log").fetchone()[0]

    asr = dict(db.execute(
        "SELECT asr_provider, COUNT(*) FROM voice_log GROUP BY asr_provider"
    ).fetchall())
    llm = dict(db.execute(
        "SELECT llm_provider, COUNT(*) FROM voice_log WHERE llm_provider IS NOT NULL GROUP BY llm_provider"
    ).fetchall())

    # Rough cost estimate (CNY/month based on current 30-day usage)
    # Qwen ASR: ~0.01 CNY/min, OpenAI Whisper: ~0.04 CNY/min, LLM: ~0.002 CNY/call
    days_active = max(1, db.execute(
        "SELECT COUNT(DISTINCT substr(created_at, 1, 10)) FROM voice_log"
    ).fetchone()[0])
    daily_dur = total_dur / days_active / 60  # minutes per day
    monthly_dur = daily_dur * 30

    qwen_pct = asr.get("qwen", 0) / max(total, 1)
    whisper_pct = asr.get("openai_whisper", 0) / max(total, 1)
    asr_cost = monthly_dur * (qwen_pct * 0.01 + whisper_pct * 0.04)
    llm_cost = (total / max(days_active, 1)) * 30 * 0.002
    estimated = asr_cost + llm_cost

    db.close()

    return UsageStats(
        total_recordings=total,
        total_duration_min=total_dur / 60,
        today_recordings=today_count,
        today_duration_min=today_dur / 60,
        asr_breakdown=asr,
        llm_breakdown=llm,
        avg_latency_ms=avg_lat,
        estimated_monthly_cost_cny=estimated,
    )
