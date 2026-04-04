"""Minimal Obsidian markdown sink for VoxLog digests."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass
class ObsidianExportResult:
    vault_path: str
    note_path: str
    bytes_written: int


class ObsidianSink:
    def __init__(self, vault_dir: Path):
        self.vault_dir = Path(vault_dir).expanduser()

    def export_digest(
        self,
        *,
        scope: str,
        content: str,
        session_id: str = "",
        digest_date: str = "",
        project_key: str = "",
    ) -> ObsidianExportResult:
        self.vault_dir.mkdir(parents=True, exist_ok=True)
        target = self._target_path(
            scope=scope.strip().lower(),
            session_id=session_id.strip(),
            digest_date=digest_date.strip(),
            project_key=project_key.strip().lower(),
        )
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        return ObsidianExportResult(
            vault_path=str(self.vault_dir),
            note_path=str(target),
            bytes_written=len(content.encode("utf-8")),
        )

    def _target_path(self, *, scope: str, session_id: str, digest_date: str, project_key: str) -> Path:
        if scope == "session":
            key = session_id or "unknown-session"
            return self.vault_dir / "VoxLog" / "Sessions" / f"{key}.md"
        if scope == "daily":
            key = digest_date or "unknown-day"
            return self.vault_dir / "VoxLog" / "Daily" / f"{key}.md"
        if scope == "project":
            key = project_key or "unknown-project"
            return self.vault_dir / "VoxLog" / "Projects" / f"{key}.md"
        return self.vault_dir / "VoxLog" / "Inbox" / f"{scope or 'digest'}.md"
