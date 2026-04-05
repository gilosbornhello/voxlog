"""Enhanced Obsidian sync with agent/task/session awareness."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

VOICE_LOG_DIR = Path.home() / "obsidian-vault" / "06-osborn" / "voice-logs"


def sync_day(db_path: Path, date_str: str) -> bool:
    """Sync one day's voice logs to Obsidian with enhanced metadata."""
    import sqlite3
    db = sqlite3.connect(str(db_path))

    rows = db.execute(
        """SELECT created_at, raw_text, display_text, polished_text,
                  stt_provider, target_app, role, agent, recording_mode
           FROM voice_events
           WHERE substr(created_at, 1, 10) = ? AND recording_mode = 'normal'
           ORDER BY created_at ASC""",
        (date_str,),
    ).fetchall()

    if not rows:
        db.close()
        return False

    VOICE_LOG_DIR.mkdir(parents=True, exist_ok=True)
    out_path = VOICE_LOG_DIR / f"{date_str}-voice-log.md"

    # Check if update needed
    if out_path.exists():
        existing_count = out_path.read_text().count("## ")
        if existing_count >= len(rows):
            db.close()
            return False

    # Collect agent stats
    agent_counts: dict[str, int] = {}
    for r in rows:
        agent = r[7] or "general"
        agent_counts[agent] = agent_counts.get(agent, 0) + 1

    # Build markdown
    lines = [
        "---",
        f"date: {date_str}",
        f"recordings: {len(rows)}",
        f"agents: {json.dumps(agent_counts)}",
        "tags: [voxlog, voice-log]",
        "---",
        "",
        f"# Voice Log: {date_str}",
        "",
        f"> {len(rows)} recordings | Agents: {', '.join(f'{k}({v})' for k,v in sorted(agent_counts.items()))}",
        "",
    ]

    current_agent = ""
    for ts, raw, display, polished, stt, app, role, agent, mode in rows:
        time_part = ts[11:19] if len(ts) > 19 else ts
        text = polished or display or raw
        role_icon = "🎤" if role == "me" else "📋"
        agent_tag = f" `{agent}`" if agent and agent != current_agent else ""
        if agent and agent != current_agent:
            current_agent = agent
            lines.append(f"### {agent}")
            lines.append("")

        app_tag = f" [{app}]" if app else ""
        lines.append(f"## {time_part}{app_tag} {role_icon}{agent_tag}")
        lines.append("")
        lines.append(text)
        lines.append("")

    # Tasks for the day
    task_rows = db.execute(
        """SELECT title, status, assigned_context_id, created_at
           FROM tasks WHERE substr(created_at, 1, 10) = ?""",
        (date_str,),
    ).fetchall() if _table_exists(db, "tasks") else []

    if task_rows:
        lines.append("---")
        lines.append("## Tasks")
        lines.append("")
        for title, status, assigned, created in task_rows:
            lines.append(f"- [{status}] {title} (→ {assigned})")
        lines.append("")

    out_path.write_text("\n".join(lines), encoding="utf-8")
    db.close()
    return True


def sync_recent(db_path: Path, days: int = 7) -> list[str]:
    now = datetime.now(timezone.utc)
    exported = []
    for i in range(days + 1):
        date_str = (now - timedelta(days=i)).strftime("%Y-%m-%d")
        if sync_day(db_path, date_str):
            exported.append(date_str)
    return exported


def _table_exists(db, name: str) -> bool:
    cursor = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (name,))
    return cursor.fetchone() is not None
