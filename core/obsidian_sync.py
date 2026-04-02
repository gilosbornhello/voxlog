"""Enhanced Obsidian sync — structured voice logs with metadata.

Exports voice logs to Obsidian with proper frontmatter, tags, and links.
Creates a daily note + an index note for easy navigation.
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

VOICE_LOG_DIR = Path.home() / "obsidian-vault" / "06-osborn" / "voice-logs"


def sync_day(db_path: Path, date_str: str) -> tuple[bool, str]:
    """Sync one day's voice logs to Obsidian. Returns (exported, filepath)."""
    db = sqlite3.connect(str(db_path))
    rows = db.execute(
        "SELECT created_at, raw_text, polished_text, asr_provider, llm_provider, "
        "polished, duration_seconds, latency_ms, target_app, env "
        "FROM voice_log WHERE created_at LIKE ? ORDER BY created_at ASC",
        (f"{date_str}%",),
    ).fetchall()
    db.close()

    if not rows:
        return False, ""

    VOICE_LOG_DIR.mkdir(parents=True, exist_ok=True)
    out_path = VOICE_LOG_DIR / f"{date_str}-voice-log.md"

    # Check if update needed
    if out_path.exists():
        existing_count = out_path.read_text().count("## ")
        if existing_count >= len(rows):
            return False, str(out_path)

    # Calculate stats
    total_duration = sum(r[6] for r in rows)
    total_latency = sum(r[7] for r in rows)
    avg_latency = total_latency / len(rows) if rows else 0
    apps = {}
    for r in rows:
        app = r[8] or "Unknown"
        apps[app] = apps.get(app, 0) + 1

    # Build markdown with frontmatter
    lines = [
        "---",
        f"date: {date_str}",
        f"recordings: {len(rows)}",
        f"duration_min: {total_duration / 60:.1f}",
        f"avg_latency_ms: {avg_latency:.0f}",
        "tags: [voxlog, voice-log]",
        "---",
        "",
        f"# Voice Log: {date_str}",
        "",
        f"> {len(rows)} recordings | {total_duration / 60:.1f} min | avg {avg_latency:.0f}ms",
        "",
    ]

    # Top apps
    if apps:
        app_str = ", ".join(f"{k}: {v}" for k, v in sorted(apps.items(), key=lambda x: -x[1]))
        lines.append(f"> Apps: {app_str}")
        lines.append("")

    for ts, raw, polished, asr, llm, is_polished, dur, lat, app, env in rows:
        time_part = ts[11:19] if len(ts) > 19 else ts
        app_tag = f" [{app}]" if app else ""
        text = polished if is_polished and polished else raw

        lines.append(f"## {time_part}{app_tag}")
        lines.append("")
        lines.append(text)
        lines.append("")

    out_path.write_text("\n".join(lines), encoding="utf-8")
    return True, str(out_path)


def sync_recent(db_path: Path, days: int = 7) -> list[str]:
    """Sync recent days to Obsidian. Returns list of exported file paths."""
    now = datetime.now(timezone.utc)
    exported = []

    for i in range(days + 1):  # Include today
        date_str = (now - timedelta(days=i)).strftime("%Y-%m-%d")
        ok, path = sync_day(db_path, date_str)
        if ok:
            exported.append(path)

    # Update index
    _update_index(db_path)
    return exported


def _update_index(db_path: Path):
    """Create/update an index note listing all voice log days."""
    VOICE_LOG_DIR.mkdir(parents=True, exist_ok=True)

    # Find all voice log files
    logs = sorted(VOICE_LOG_DIR.glob("*-voice-log.md"), reverse=True)

    lines = [
        "---",
        "tags: [voxlog, index]",
        "---",
        "",
        "# VoxLog Index",
        "",
        "> All voice recordings, organized by date.",
        "> Auto-updated by VoxLog.",
        "",
    ]

    current_month = ""
    for log in logs:
        date_str = log.stem.replace("-voice-log", "")
        month = date_str[:7]  # YYYY-MM
        if month != current_month:
            current_month = month
            lines.append(f"### {month}")
            lines.append("")

        # Read frontmatter for stats
        content = log.read_text(encoding="utf-8")
        recordings = "?"
        duration = "?"
        for line in content.split("\n"):
            if line.startswith("recordings:"):
                recordings = line.split(":")[1].strip()
            elif line.startswith("duration_min:"):
                duration = line.split(":")[1].strip()

        lines.append(f"- [[{date_str}-voice-log|{date_str}]] — {recordings} recordings, {duration} min")

    lines.append("")

    index_path = VOICE_LOG_DIR / "VoxLog-Index.md"
    index_path.write_text("\n".join(lines), encoding="utf-8")
