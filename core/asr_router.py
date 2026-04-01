"""ASR routing with failover.

Main provider times out (3s default) -> automatically switch to fallback.
Both fail -> raise ASRError.
"""

from __future__ import annotations

import asyncio
import time
from typing import Protocol

import httpx
import structlog

from core.config import VoxLogConfig
from core.models import ASRProvider, TranscribeResult

logger = structlog.get_logger()


class ASRError(Exception):
    pass


class ASRProviderClient(Protocol):
    async def transcribe(self, audio: bytes) -> str: ...


class QwenASR:
    """Alibaba Qwen ASR via DashScope MultiModalConversation API.

    Uses qwen3-asr-flash model. Audio is sent as base64 data URI.
    For China domestic: dashscope.aliyuncs.com
    For international: dashscope-intl.aliyuncs.com
    """

    def __init__(self, api_key: str, international: bool = False):
        self.api_key = api_key
        host = "dashscope-intl.aliyuncs.com" if international else "dashscope.aliyuncs.com"
        self.base_url = f"https://{host}/api/v1"

    async def transcribe(self, audio: bytes) -> str:
        import base64
        audio_b64 = base64.b64encode(audio).decode()
        data_uri = f"data:audio/wav;base64,{audio_b64}"

        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{self.base_url}/services/aigc/multimodal-generation/generation",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": "qwen3-asr-flash",
                    "input": {
                        "messages": [
                            {"content": [{"audio": data_uri}], "role": "user"},
                        ]
                    },
                    "parameters": {
                        "asr_options": {"enable_itn": True}
                    },
                },
            )
            resp.raise_for_status()
            data = resp.json()
            # Extract text from multimodal response
            content = data.get("output", {}).get("choices", [{}])[0].get("message", {}).get("content", [])
            if isinstance(content, list):
                return "".join(c.get("text", "") for c in content if "text" in c).strip()
            if isinstance(content, str):
                return content.strip()
            raise ASRError(f"Unexpected Qwen ASR response format: {data}")


class OpenAIWhisper:
    """OpenAI Whisper API."""

    def __init__(self, api_key: str):
        self.api_key = api_key

    async def transcribe(self, audio: bytes) -> str:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                files={"file": ("audio.wav", audio, "audio/wav")},
                data={"model": "whisper-1"},
            )
            resp.raise_for_status()
            return resp.json()["text"]


class LocalWhisper:
    """Local faster-whisper inference."""

    def __init__(self):
        self._model = None

    def _ensure_model(self):
        if self._model is None:
            try:
                from faster_whisper import WhisperModel
                self._model = WhisperModel("large-v3", device="auto", compute_type="auto")
            except ImportError:
                raise ASRError("faster-whisper not installed. Run: pip install 'voxlog[local]'")

    async def transcribe(self, audio: bytes) -> str:
        import tempfile
        self._ensure_model()
        # faster-whisper needs a file path
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as f:
            f.write(audio)
            f.flush()
            segments, _ = await asyncio.to_thread(
                self._model.transcribe, f.name, language=None
            )
            return " ".join(s.text.strip() for s in segments)


def _get_client(provider: ASRProvider, config: VoxLogConfig) -> ASRProviderClient:
    if provider == ASRProvider.QWEN:
        # Home (US exit) uses international endpoint; Office (China) uses domestic
        from core.models import Environment
        international = config.env == Environment.HOME
        return QwenASR(config.dashscope_api_key, international=international)
    elif provider == ASRProvider.OPENAI_WHISPER:
        return OpenAIWhisper(config.openai_api_key)
    elif provider == ASRProvider.LOCAL_WHISPER:
        return LocalWhisper()
    raise ASRError(f"Unknown ASR provider: {provider}")


async def transcribe(audio: bytes, config: VoxLogConfig) -> TranscribeResult:
    """Transcribe audio with failover. Main -> fallback -> error."""
    route = config.route
    main_provider = route.asr.main
    fallback_provider = route.asr.fallback
    timeout = route.asr.timeout_seconds

    # Try main provider
    start = time.monotonic()
    try:
        client = _get_client(main_provider, config)
        text = await asyncio.wait_for(client.transcribe(audio), timeout=timeout)
        latency = int((time.monotonic() - start) * 1000)
        logger.info("asr.success", provider=main_provider.value, latency_ms=latency)
        return TranscribeResult(raw_text=text, provider=main_provider, latency_ms=latency)
    except (asyncio.TimeoutError, httpx.HTTPError, ASRError) as e:
        logger.warning("asr.main_failed", provider=main_provider.value, error=str(e))

    # Try fallback
    start = time.monotonic()
    try:
        client = _get_client(fallback_provider, config)
        text = await asyncio.wait_for(client.transcribe(audio), timeout=timeout * 3)
        latency = int((time.monotonic() - start) * 1000)
        logger.info("asr.fallback_success", provider=fallback_provider.value, latency_ms=latency)
        return TranscribeResult(raw_text=text, provider=fallback_provider, latency_ms=latency)
    except (asyncio.TimeoutError, httpx.HTTPError, ASRError) as e:
        logger.error("asr.both_failed", fallback=fallback_provider.value, error=str(e))
        raise ASRError(f"Both ASR providers failed. Main: {main_provider}, Fallback: {fallback_provider}")
