#!/usr/bin/env python3
"""VoxLog2 CLI — query your voice history from the terminal.

Usage:
    python cli.py today                    # Today's voice log
    python cli.py search "pricing"         # Search all history
    python cli.py date 2026-04-01          # Specific date
    python cli.py export 2026-04-01        # Export Markdown for Obsidian
    python cli.py export today             # Export today to Obsidian
    python cli.py stats                    # Usage statistics
    python cli.py tail                     # Last 10 entries
    python cli.py suggest-terms            # Suggest new dictionary terms
    python cli.py summary [date]           # AI-generated daily summary (needs server)
"""

from __future__ import annotations

import asyncio
import os
import sqlite3
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

DB_PATH = Path.home() / ".voxlog2" / "history.db"
OBSIDIAN_VOICE_DIR = Path.home() / "obsidian-vault" / "06-osborn" / "voice-logs"


def get_db():
    if not DB_PATH.exists():
        print("No voice history found. Start recording first!")
        sys.exit(1)
    return sqlite3.connect(str(DB_PATH))


def today_str():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def cmd_today():
    db = get_db()
    rows = db.execute(
        "SELECT created_at, polished_text, target_app, polished FROM voice_log "
        "WHERE created_at LIKE ? ORDER BY created_at ASC",
        (f"{today_str()}%",),
    ).fetchall()
    if not rows:
        print("No recordings today.")
        return
    print(f"=== Voice Log: {today_str()} ({len(rows)} entries) ===\n")
    for ts, text, app, polished in rows:
        time_part = ts[11:19] if len(ts) > 19 else ts
        app_tag = f" [{app}]" if app else ""
        raw_tag = " (raw)" if not polished else ""
        print(f"  {time_part}{app_tag}{raw_tag}")
        print(f"  {text}\n")


def cmd_search(query: str):
    db = get_db()
    rows = db.execute(
        "SELECT created_at, polished_text, target_app FROM voice_log "
        "WHERE polished_text LIKE ? OR raw_text LIKE ? "
        "ORDER BY created_at DESC LIMIT 50",
        (f"%{query}%", f"%{query}%"),
    ).fetchall()
    if not rows:
        print(f'No results for "{query}".')
        return
    print(f'=== Search: "{query}" ({len(rows)} results) ===\n')
    for ts, text, app in rows:
        date_part = ts[:10]
        time_part = ts[11:19] if len(ts) > 19 else ts
        app_tag = f" [{app}]" if app else ""
        print(f"  {date_part} {time_part}{app_tag}")
        # Highlight search term
        highlighted = text.replace(query, f"\033[1;33m{query}\033[0m")
        print(f"  {highlighted}\n")


def cmd_date(date_str: str):
    db = get_db()
    rows = db.execute(
        "SELECT created_at, polished_text, target_app, polished FROM voice_log "
        "WHERE created_at LIKE ? ORDER BY created_at ASC",
        (f"{date_str}%",),
    ).fetchall()
    if not rows:
        print(f"No recordings on {date_str}.")
        return
    print(f"=== Voice Log: {date_str} ({len(rows)} entries) ===\n")
    for ts, text, app, polished in rows:
        time_part = ts[11:19] if len(ts) > 19 else ts
        app_tag = f" [{app}]" if app else ""
        raw_tag = " (raw)" if not polished else ""
        print(f"  {time_part}{app_tag}{raw_tag}")
        print(f"  {text}\n")


def cmd_export(date_str: str):
    if date_str == "today":
        date_str = today_str()

    db = get_db()
    rows = db.execute(
        "SELECT created_at, polished_text, target_app, polished FROM voice_log "
        "WHERE created_at LIKE ? ORDER BY created_at ASC",
        (f"{date_str}%",),
    ).fetchall()
    if not rows:
        print(f"No recordings on {date_str}. Nothing to export.")
        return

    # Build Markdown
    lines = [f"# Voice Log: {date_str}\n"]
    for ts, text, app, polished in rows:
        time_part = ts[11:19] if len(ts) > 19 else ts
        app_tag = f" [{app}]" if app else ""
        raw_tag = " (raw)" if not polished else ""
        lines.append(f"## {time_part}{app_tag}{raw_tag}\n")
        lines.append(f"{text}\n")

    md = "\n".join(lines)

    # Write to Obsidian vault
    OBSIDIAN_VOICE_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OBSIDIAN_VOICE_DIR / f"{date_str}-voice-log.md"
    out_path.write_text(md, encoding="utf-8")
    print(f"Exported {len(rows)} entries to {out_path}")


def cmd_stats():
    db = get_db()
    total = db.execute("SELECT COUNT(*) FROM voice_log").fetchone()[0]
    if total == 0:
        print("No recordings yet.")
        return

    # Total duration
    total_duration = db.execute("SELECT SUM(duration_seconds) FROM voice_log").fetchone()[0] or 0

    # Date range
    first = db.execute("SELECT MIN(created_at) FROM voice_log").fetchone()[0]
    last = db.execute("SELECT MAX(created_at) FROM voice_log").fetchone()[0]

    # By provider
    providers = db.execute(
        "SELECT asr_provider, COUNT(*) FROM voice_log GROUP BY asr_provider"
    ).fetchall()

    # By app
    apps = db.execute(
        "SELECT target_app, COUNT(*) FROM voice_log WHERE target_app != '' "
        "GROUP BY target_app ORDER BY COUNT(*) DESC LIMIT 10"
    ).fetchall()

    # Average latency
    avg_latency = db.execute("SELECT AVG(latency_ms) FROM voice_log").fetchone()[0] or 0

    # Today count
    today_count = db.execute(
        "SELECT COUNT(*) FROM voice_log WHERE created_at LIKE ?",
        (f"{today_str()}%",),
    ).fetchone()[0]

    print("=== VoxLog Stats ===\n")
    print(f"  Total recordings:  {total}")
    print(f"  Total duration:    {total_duration / 60:.1f} minutes")
    print(f"  Today:             {today_count}")
    print(f"  Avg latency:       {avg_latency:.0f}ms")
    print(f"  First recording:   {first[:19] if first else 'N/A'}")
    print(f"  Latest recording:  {last[:19] if last else 'N/A'}")
    print()
    print("  ASR providers:")
    for provider, count in providers:
        print(f"    {provider}: {count}")
    if apps:
        print()
        print("  Top target apps:")
        for app, count in apps:
            print(f"    {app}: {count}")


def cmd_tail(n: int = 10):
    db = get_db()
    rows = db.execute(
        "SELECT created_at, polished_text, target_app FROM voice_log "
        "ORDER BY created_at DESC LIMIT ?",
        (n,),
    ).fetchall()
    if not rows:
        print("No recordings yet.")
        return
    print(f"=== Last {len(rows)} recordings ===\n")
    for ts, text, app in reversed(rows):
        date_part = ts[:10]
        time_part = ts[11:19] if len(ts) > 19 else ts
        app_tag = f" [{app}]" if app else ""
        print(f"  {date_part} {time_part}{app_tag}")
        print(f"  {text}\n")


def cmd_summary(date_str: str = "today"):
    """Generate AI summary of a day's voice log. Requires server running."""
    import httpx
    if date_str == "today":
        date_str = today_str()
    try:
        resp = httpx.get(
            f"http://127.0.0.1:7890/v1/summary?date={date_str}",
            headers={"Authorization": "Bearer voxlog-dev-token"},
            timeout=60.0,
        )
        resp.raise_for_status()
        data = resp.json()
        print(f"=== Daily Summary: {data['date']} ({data['record_count']} recordings) ===\n")
        print(data["summary"])
    except httpx.ConnectError:
        print("Server not running. Start it first: voxlog-server")
    except Exception as e:
        print(f"Error: {e}")


def cmd_suggest_terms():
    """Analyze raw_text vs polished_text to find frequently corrected words."""
    db = get_db()
    rows = db.execute(
        "SELECT raw_text, polished_text FROM voice_log WHERE polished = 1"
    ).fetchall()
    if not rows:
        print("No polished recordings to analyze.")
        return

    # Simple diff: find words in raw that don't appear in polished
    corrections = Counter()
    for raw, polished in rows:
        raw_words = set(raw.lower().split())
        polished_words = set(polished.lower().split())
        # Words that appear in raw but not in polished (likely corrected)
        removed = raw_words - polished_words
        for word in removed:
            if len(word) > 1:  # Skip single chars
                corrections[word] += 1

    if not corrections:
        print("No correction patterns found yet. Need more recordings.")
        return

    print("=== Suggested Dictionary Terms ===")
    print("Words frequently removed/corrected by LLM:\n")
    for word, count in corrections.most_common(20):
        if count >= 2:  # Only show if appeared 2+ times
            print(f"  {word}: corrected {count} times")
    print()
    print("Add frequent corrections to terms.json to speed up processing.")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    cmd = sys.argv[1]

    if cmd == "today":
        cmd_today()
    elif cmd == "search" and len(sys.argv) > 2:
        cmd_search(sys.argv[2])
    elif cmd == "date" and len(sys.argv) > 2:
        cmd_date(sys.argv[2])
    elif cmd == "export" and len(sys.argv) > 2:
        cmd_export(sys.argv[2])
    elif cmd == "stats":
        cmd_stats()
    elif cmd == "tail":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 10
        cmd_tail(n)
    elif cmd == "suggest-terms":
        cmd_suggest_terms()
    elif cmd == "summary":
        date_str = sys.argv[2] if len(sys.argv) > 2 else "today"
        cmd_summary(date_str)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
