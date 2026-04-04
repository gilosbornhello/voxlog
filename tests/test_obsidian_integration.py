"""Tests for the minimal Obsidian digest export sink."""

from pathlib import Path

from integrations.obsidian import ObsidianSink


def test_obsidian_sink_exports_project_digest(tmp_path: Path):
    vault = tmp_path / "Vault"
    sink = ObsidianSink(vault)

    result = sink.export_digest(
        scope="project",
        project_key="cursor",
        content="# project_digest\n\ncursor digest body\n",
    )

    note_path = Path(result.note_path)
    assert note_path.exists()
    assert note_path.name == "cursor.md"
    assert "cursor digest body" in note_path.read_text(encoding="utf-8")
    assert result.bytes_written > 0
