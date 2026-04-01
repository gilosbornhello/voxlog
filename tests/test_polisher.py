"""Tests for core.polisher — LLM polish with graceful degradation."""

import asyncio
from unittest.mock import AsyncMock, patch

import pytest

from core.config import VoxLogConfig
from core.dictionary import Dictionary
from core.models import Environment, LLMProvider
from core.polisher import polish


@pytest.fixture
def config():
    return VoxLogConfig(env=Environment.HOME)


@pytest.fixture
def dictionary():
    return Dictionary(None)  # Empty dictionary for tests


@pytest.fixture
def dict_with_corrections(tmp_path):
    import json
    terms = {"corrections": {"open claw": "OpenClaw"}, "format_rules": {"cn_en_space": True}}
    path = tmp_path / "terms.json"
    path.write_text(json.dumps(terms))
    return Dictionary(path)


class TestPolisher:
    async def test_success(self, config, dictionary):
        with patch("core.polisher._call_llm", new_callable=AsyncMock) as mock:
            mock.return_value = "polished text"
            result = await polish("raw text", dictionary, config)
            assert result.polished_text == "polished text"
            assert result.polished is True

    async def test_empty_text(self, config, dictionary):
        result = await polish("", dictionary, config)
        assert result.polished_text == ""
        assert result.polished is False

    async def test_whitespace_only(self, config, dictionary):
        result = await polish("   ", dictionary, config)
        assert result.polished_text == ""
        assert result.polished is False

    async def test_timeout_degradation(self, config, dictionary):
        with patch("core.polisher._call_llm", new_callable=AsyncMock) as mock:
            mock.side_effect = asyncio.TimeoutError()
            result = await polish("raw text", dictionary, config)
            assert result.polished_text == "raw text"
            assert result.polished is False

    async def test_http_error_degradation(self, config, dictionary):
        import httpx
        with patch("core.polisher._call_llm", new_callable=AsyncMock) as mock:
            mock.side_effect = httpx.ConnectError("connection refused")
            result = await polish("raw text", dictionary, config)
            assert result.polished_text == "raw text"
            assert result.polished is False

    async def test_dictionary_applied_before_llm(self, config, dict_with_corrections):
        captured_input = None

        async def capture_llm(text, provider, cfg):
            nonlocal captured_input
            captured_input = text
            return text + " (polished)"

        with patch("core.polisher._call_llm", side_effect=capture_llm):
            result = await polish("open claw is great", dict_with_corrections, config)
            # Dictionary should have corrected before LLM sees it
            assert "OpenClaw" in captured_input
            assert result.polished is True

    async def test_dictionary_applied_on_degradation(self, config, dict_with_corrections):
        with patch("core.polisher._call_llm", new_callable=AsyncMock) as mock:
            mock.side_effect = asyncio.TimeoutError()
            result = await polish("open claw rocks", dict_with_corrections, config)
            # Even when LLM fails, dictionary corrections should be applied
            assert "OpenClaw" in result.polished_text
            assert result.polished is False

    async def test_main_fail_fallback_success(self, config, dictionary):
        call_count = 0

        async def mock_llm(text, provider, cfg):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise asyncio.TimeoutError()
            return "fallback polished"

        with patch("core.polisher._call_llm", side_effect=mock_llm):
            result = await polish("test", dictionary, config)
            assert result.polished_text == "fallback polished"
            assert result.polished is True
