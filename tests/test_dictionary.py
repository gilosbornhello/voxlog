"""Tests for core.dictionary — term corrections and formatting."""

import json
import tempfile
from pathlib import Path

from core.dictionary import Dictionary


def _write_terms(data: dict) -> Path:
    f = tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False)
    json.dump(data, f)
    f.close()
    return Path(f.name)


class TestDictionaryLoad:
    def test_load_valid_terms(self):
        path = _write_terms({"corrections": {"foo": "bar"}, "preserve": ["bar"]})
        d = Dictionary(path)
        assert d.corrections == {"foo": "bar"}
        assert d.preserve == ["bar"]

    def test_load_missing_file(self):
        d = Dictionary(Path("/nonexistent/terms.json"))
        assert d.corrections == {}
        assert d.preserve == []

    def test_load_invalid_json(self):
        f = tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False)
        f.write("{invalid json")
        f.close()
        d = Dictionary(Path(f.name))
        assert d.corrections == {}

    def test_load_none_path(self):
        d = Dictionary(None)
        assert d.corrections == {}


class TestDictionaryApply:
    def test_apply_corrections(self):
        path = _write_terms({"corrections": {"open claw": "OpenClaw", "os born": "OSBORN"}})
        d = Dictionary(path)
        assert d.apply("open claw is made by os born") == "OpenClaw is made by OSBORN"

    def test_case_insensitive_correction(self):
        path = _write_terms({"corrections": {"open claw": "OpenClaw"}})
        d = Dictionary(path)
        assert d.apply("Open Claw rocks") == "OpenClaw rocks"

    def test_cn_en_space(self):
        path = _write_terms({"corrections": {}, "format_rules": {"cn_en_space": True}})
        d = Dictionary(path)
        assert d.apply("把首页pricing放到hero下面") == "把首页 pricing 放到 hero 下面"

    def test_cn_en_space_disabled(self):
        path = _write_terms({"corrections": {}, "format_rules": {"cn_en_space": False}})
        d = Dictionary(path)
        assert d.apply("把首页pricing放到hero下面") == "把首页pricing放到hero下面"

    def test_empty_text(self):
        d = Dictionary(None)
        assert d.apply("") == ""

    def test_combined_correction_and_spacing(self):
        path = _write_terms({
            "corrections": {"cloud code": "Claude Code"},
            "format_rules": {"cn_en_space": True},
        })
        d = Dictionary(path)
        result = d.apply("用cloud code写代码")
        assert "Claude Code" in result
        # Chinese-English space should be applied
        assert "用 Claude Code 写代码" == result
