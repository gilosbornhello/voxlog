"""Multi-format voice log exporter.

Exports voice history to various formats for different use cases:
- Markdown (Obsidian)
- JSON (API/backup)
- CSV (spreadsheet analysis)
- Plain text (simple review)
"""

from __future__ import annotations

import csv
import io
import json
import sqlite3
from datetime import datetime
from pathlib import Path


def export_json(db_path: Path, date_str: str) -> str:
    db = sqlite3.connect(str(db_path))
    rows = db.execute(
        "SELECT id, created_at, raw_text, polished_text, asr_provider, llm_provider, "
        "polished, duration_seconds, latency_ms, target_app, env "
        "FROM voice_log WHERE created_at LIKE ? ORDER BY created_at ASC",
        (f"{date_str}%",),
    ).fetchall()
    db.close()

    records = []
    for r in rows:
        records.append({
            "id": r[0], "created_at": r[1], "raw_text": r[2], "polished_text": r[3],
            "asr_provider": r[4], "llm_provider": r[5], "polished": bool(r[6]),
            "duration_seconds": r[7], "latency_ms": r[8], "target_app": r[9], "env": r[10],
        })
    return json.dumps({"date": date_str, "count": len(records), "records": records},
                       ensure_ascii=False, indent=2)


def export_csv(db_path: Path, date_str: str) -> str:
    db = sqlite3.connect(str(db_path))
    rows = db.execute(
        "SELECT created_at, polished_text, raw_text, asr_provider, latency_ms, "
        "duration_seconds, target_app, env "
        "FROM voice_log WHERE created_at LIKE ? ORDER BY created_at ASC",
        (f"{date_str}%",),
    ).fetchall()
    db.close()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["time", "text", "raw_text", "asr", "latency_ms", "duration_s", "app", "env"])
    for r in rows:
        writer.writerow(r)
    return output.getvalue()


def export_plaintext(db_path: Path, date_str: str) -> str:
    db = sqlite3.connect(str(db_path))
    rows = db.execute(
        "SELECT created_at, polished_text FROM voice_log "
        "WHERE created_at LIKE ? ORDER BY created_at ASC",
        (f"{date_str}%",),
    ).fetchall()
    db.close()

    if not rows:
        return f"No voice records for {date_str}."

    lines = [f"Voice Log: {date_str}\n"]
    for ts, text in rows:
        time_part = ts[11:19] if len(ts) > 19 else ts
        lines.append(f"[{time_part}] {text}")
    return "\n".join(lines)


def export_weekly_summary(db_path: Path, end_date: str) -> str:
    """Export a week's worth of voice logs as a single Markdown document."""
    from datetime import timedelta
    end = datetime.strptime(end_date, "%Y-%m-%d")
    start = end - timedelta(days=6)

    db = sqlite3.connect(str(db_path))

    lines = [f"# Weekly Voice Log: {start.strftime('%Y-%m-%d')} to {end_date}\n"]

    total_count = 0
    total_duration = 0.0

    for i in range(7):
        day = (start + timedelta(days=i)).strftime("%Y-%m-%d")
        rows = db.execute(
            "SELECT created_at, polished_text, target_app, duration_seconds "
            "FROM voice_log WHERE created_at LIKE ? ORDER BY created_at ASC",
            (f"{day}%",),
        ).fetchall()

        if not rows:
            continue

        day_duration = sum(r[3] for r in rows)
        total_count += len(rows)
        total_duration += day_duration

        lines.append(f"## {day} ({len(rows)} recordings, {day_duration/60:.1f} min)\n")
        for ts, text, app, _ in rows:
            time_part = ts[11:19] if len(ts) > 19 else ts
            app_tag = f" [{app}]" if app else ""
            lines.append(f"- **{time_part}**{app_tag} {text}")
        lines.append("")

    lines.insert(1, f"> {total_count} recordings | {total_duration/60:.1f} minutes total\n")

    db.close()
    return "\n".join(lines)
