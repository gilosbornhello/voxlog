"""Personal dictionary for term corrections.

Loads terms.json and applies corrections to ASR output before LLM polish.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import structlog

logger = structlog.get_logger()


class Dictionary:
    def __init__(self, terms_path: Path | None = None):
        self.corrections: dict[str, str] = {}
        self.preserve: list[str] = []
        self.cn_en_space: bool = True
        if terms_path and terms_path.exists():
            self._load(terms_path)

    def _load(self, path: Path) -> None:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            self.corrections = data.get("corrections", {})
            self.preserve = data.get("preserve", [])
            rules = data.get("format_rules", {})
            self.cn_en_space = rules.get("cn_en_space", True)
            logger.info("dictionary.loaded", corrections=len(self.corrections), preserve=len(self.preserve))
        except (json.JSONDecodeError, KeyError) as e:
            logger.warning("dictionary.load_failed", error=str(e), path=str(path))
            # Fallback to empty dictionary — don't crash

    def apply(self, text: str) -> str:
        if not text:
            return text

        result = text

        # Step 1: Apply corrections (case-insensitive)
        for wrong, right in self.corrections.items():
            pattern = re.compile(re.escape(wrong), re.IGNORECASE)
            result = pattern.sub(right, result)

        # Step 2: Add space between Chinese and English if enabled
        if self.cn_en_space:
            # Chinese char followed by ASCII letter/digit
            result = re.sub(r"([\u4e00-\u9fff])([A-Za-z0-9])", r"\1 \2", result)
            # ASCII letter/digit followed by Chinese char
            result = re.sub(r"([A-Za-z0-9])([\u4e00-\u9fff])", r"\1 \2", result)

        return result
