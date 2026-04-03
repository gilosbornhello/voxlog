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

    Three regions:
    - US:    dashscope-us.aliyuncs.com  + model qwen3-asr-flash-us
    - China: dashscope.aliyuncs.com     + model qwen3-asr-flash
    - Intl:  dashscope-intl.aliyuncs.com + model qwen3-asr-flash
    """

    # Region config: (base_url, model_name)
    REGIONS = {
        "us": ("https://dashscope-us.aliyuncs.com/api/v1", "qwen3-asr-flash-us"),
        "cn": ("https://dashscope.aliyuncs.com/api/v1", "qwen3-asr-flash"),
        "intl": ("https://dashscope-intl.aliyuncs.com/api/v1", "qwen3-asr-flash"),
    }

    def __init__(self, api_key: str, region: str = "us"):
        self.api_key = api_key
        self.base_url, self.model = self.REGIONS.get(region, self.REGIONS["us"])

    async def transcribe(self, audio: bytes) -> str:
        import base64
        from core.audio import detect_format
        audio_b64 = base64.b64encode(audio).decode()
        fmt = detect_format(audio)
        mime = {"wav": "audio/wav", "ogg": "audio/ogg", "amr": "audio/amr"}.get(fmt, "audio/wav")
        data_uri = f"data:{mime};base64,{audio_b64}"

        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{self.base_url}/services/aigc/multimodal-generation/generation",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": self.model,
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
        from core.audio import detect_format
        fmt = detect_format(audio)
        ext = {"wav": "wav", "ogg": "ogg", "amr": "amr"}.get(fmt, "webm")
        mime = {"wav": "audio/wav", "ogg": "audio/ogg", "amr": "audio/amr"}.get(fmt, "audio/webm")
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                files={"file": (f"audio.{ext}", audio, mime)},
                data={"model": "whisper-1"},
            )
            resp.raise_for_status()
            return resp.json()["text"]


class SiliconFlowASR:
    """SenseVoice ASR via SiliconFlow (OpenAI-compatible API).

    Free tier: 20M tokens on registration. Fast inference (5-15x faster than Whisper).
    Best option for China domestic network.
    """

    def __init__(self, api_key: str, base_url: str = "", model: str = ""):
        import os
        self.api_key = api_key
        self.base_url = base_url or os.getenv("SILICONFLOW_BASE_URL", "https://api.siliconflow.cn/v1")
        self.model = model or os.getenv("SILICONFLOW_MODEL", "FunAudioLLM/SenseVoiceSmall")

    async def transcribe(self, audio: bytes) -> str:
        from core.audio import detect_format
        fmt = detect_format(audio)
        ext = {"wav": "wav", "ogg": "ogg", "amr": "amr"}.get(fmt, "wav")
        mime = {"wav": "audio/wav", "ogg": "audio/ogg", "amr": "audio/amr"}.get(fmt, "audio/wav")
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{self.base_url}/audio/transcriptions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                files={"file": (f"audio.{ext}", audio, mime)},
                data={"model": self.model},
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
        import os
        region = os.getenv("DASHSCOPE_REGION", "us")
        # Use CN key for CN region, US key for US/intl
        if region == "cn" and config.dashscope_api_key_cn:
            key = config.dashscope_api_key_cn
        else:
            key = config.dashscope_api_key
        return QwenASR(key, region=region)
    elif provider == ASRProvider.OPENAI_WHISPER:
        return OpenAIWhisper(config.openai_api_key)
    elif provider == ASRProvider.LOCAL_WHISPER:
        return LocalWhisper()
    elif provider == ASRProvider.SILICONFLOW:
        return SiliconFlowASR(config.siliconflow_api_key)
    raise ASRError(f"Unknown ASR provider: {provider}")


def _resolve_override(override: str | None, config: VoxLogConfig) -> tuple[ASRProvider, ASRProvider]:
    """Resolve ASR override string to provider + fallback."""
    mapping = {
        "qwen-us": ASRProvider.QWEN,
        "qwen-cn": ASRProvider.QWEN,
        "openai": ASRProvider.OPENAI_WHISPER,
        "siliconflow": ASRProvider.SILICONFLOW,
    }
    if override and override in mapping:
        main = mapping[override]
        import os
        if override == "qwen-cn":
            os.environ["DASHSCOPE_REGION"] = "cn"
        elif override == "qwen-us":
            os.environ["DASHSCOPE_REGION"] = "us"
        # Pick a different fallback
        fallback = ASRProvider.OPENAI_WHISPER if main != ASRProvider.OPENAI_WHISPER else ASRProvider.QWEN
        return main, fallback
    return config.route.asr.main, config.route.asr.fallback


async def transcribe(audio: bytes, config: VoxLogConfig, asr_override: str | None = None) -> TranscribeResult:
    """Transcribe audio with failover. Main -> fallback -> error."""
    main_provider, fallback_provider = _resolve_override(asr_override, config)
    timeout = config.route.asr.timeout_seconds

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
