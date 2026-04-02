#!/usr/bin/env python3
"""Auto-sync voice logs to Obsidian vault.

Designed to run daily via cron/launchd:
    0 2 * * * cd ~/voxlog && .venv/bin/python export_cron.py

Syncs past 7 days + today. Creates per-day markdown files with
frontmatter and a VoxLog-Index.md for navigation.
"""

from __future__ import annotations

from pathlib import Path

from core.obsidian_sync import sync_recent

DB_PATH = Path.home() / ".voxlog" / "history.db"


def main():
    if not DB_PATH.exists():
        return

    exported = sync_recent(DB_PATH, days=7)
    if exported:
        print(f"Synced {len(exported)} day(s) to Obsidian:")
        for f in exported:
            print(f"  {f}")
    else:
        print("Nothing new to sync.")


if __name__ == "__main__":
    main()
