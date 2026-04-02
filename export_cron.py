#!/usr/bin/env python3
"""Auto-export yesterday's voice log to Obsidian vault.

Designed to run daily via cron/launchd:
    0 2 * * * cd ~/voxlog && .venv/bin/python export_cron.py

Also exports any missing days from the past 7 days.
"""

from __future__ import annotations

import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

DB_PATH = Path.home() / ".voxlog" / "history.db"
OBSIDIAN_VOICE_DIR = Path.home() / "obsidian-vault" / "06-osborn" / "voice-logs"


def export_date(db: sqlite3.Connection, date_str: str) -> bool:
    rows = db.execute(
        "SELECT created_at, polished_text, target_app, polished FROM voice_log "
        "WHERE created_at LIKE ? ORDER BY created_at ASC",
        (f"{date_str}%",),
    ).fetchall()

    if not rows:
        return False

    out_path = OBSIDIAN_VOICE_DIR / f"{date_str}-voice-log.md"
    if out_path.exists():
        # Already exported, check if same count
        existing_count = out_path.read_text().count("## ")
        if existing_count >= len(rows):
            return False  # No new entries

    lines = [f"# Voice Log: {date_str}\n"]
    lines.append(f"> {len(rows)} recordings | auto-exported by VoxLog\n")

    for ts, text, app, polished in rows:
        time_part = ts[11:19] if len(ts) > 19 else ts
        app_tag = f" [{app}]" if app else ""
        raw_tag = " (raw)" if not polished else ""
        lines.append(f"## {time_part}{app_tag}{raw_tag}\n")
        lines.append(f"{text}\n")

    OBSIDIAN_VOICE_DIR.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")
    return True


def main():
    if not DB_PATH.exists():
        return

    db = sqlite3.connect(str(DB_PATH))
    now = datetime.now(timezone.utc)
    exported = 0

    # Export past 7 days (catches any missed days)
    for days_ago in range(1, 8):
        date_str = (now - timedelta(days=days_ago)).strftime("%Y-%m-%d")
        if export_date(db, date_str):
            exported += 1
            print(f"Exported: {date_str}")

    # Also export today (partial, will be updated tomorrow)
    today = now.strftime("%Y-%m-%d")
    if export_date(db, today):
        exported += 1
        print(f"Exported: {today} (partial)")

    if exported:
        print(f"Total: {exported} day(s) exported to {OBSIDIAN_VOICE_DIR}")
    else:
        print("Nothing new to export.")

    db.close()


if __name__ == "__main__":
    main()
