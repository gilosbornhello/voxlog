"""Tests for core.asr_router — ASR routing with failover."""

import asyncio
from unittest.mock import AsyncMock, patch

import pytest

from core.asr_router import ASRError, transcribe
from core.config import VoxLogConfig
from core.models import ASRProvider, Environment


@pytest.fixture
def config():
    return VoxLogConfig(env=Environment.HOME)


@pytest.fixture
def audio_bytes():
    # Minimal WAV-like bytes for testing (actual ASR is mocked)
    return b"RIFF" + b"\x00" * 100


class TestASRRouter:
    async def test_main_provider_success(self, config, audio_bytes):
        with patch("core.asr_router._get_client") as mock_get:
            client = AsyncMock()
            client.transcribe.return_value = "hello world"
            mock_get.return_value = client

            result = await transcribe(audio_bytes, config)
            assert result.raw_text == "hello world"
            assert result.provider == ASRProvider.QWEN

    async def test_main_timeout_fallback_success(self, config, audio_bytes):
        call_count = 0

        async def mock_transcribe(audio):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise asyncio.TimeoutError()
            return "fallback result"

        with patch("core.asr_router._get_client") as mock_get:
            client = AsyncMock()
            client.transcribe = mock_transcribe
            mock_get.return_value = client

            result = await transcribe(audio_bytes, config)
            assert result.raw_text == "fallback result"
            assert result.provider == ASRProvider.OPENAI_WHISPER

    async def test_both_fail_raises(self, config, audio_bytes):
        with patch("core.asr_router._get_client") as mock_get:
            client = AsyncMock()
            client.transcribe.side_effect = asyncio.TimeoutError()
            mock_get.return_value = client

            with pytest.raises(ASRError, match="Both ASR providers failed"):
                await transcribe(audio_bytes, config)

    async def test_main_http_error_fallback(self, config, audio_bytes):
        import httpx

        call_count = 0

        async def mock_transcribe(audio):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise httpx.HTTPStatusError(
                    "500", request=httpx.Request("POST", "http://x"), response=httpx.Response(500)
                )
            return "fallback ok"

        with patch("core.asr_router._get_client") as mock_get:
            client = AsyncMock()
            client.transcribe = mock_transcribe
            mock_get.return_value = client

            result = await transcribe(audio_bytes, config)
            assert result.raw_text == "fallback ok"

    async def test_office_env_providers(self, audio_bytes):
        config = VoxLogConfig(env=Environment.OFFICE)
        with patch("core.asr_router._get_client") as mock_get:
            client = AsyncMock()
            client.transcribe.return_value = "office result"
            mock_get.return_value = client

            result = await transcribe(audio_bytes, config)
            assert result.raw_text == "office result"
            # First call should be for QWEN (main in office env)
            first_call_provider = mock_get.call_args_list[0][0][0]
            assert first_call_provider == ASRProvider.QWEN
