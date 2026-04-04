"""STT adapter — unified interface for all speech-to-text providers.

Fast path only: get text back as fast as possible.
"""

from __future__ import annotations

import asyncio
import base64
import time
from typing import Protocol

import httpx
import structlog

from runtime.models.config import VoxLogConfig

logger = structlog.get_logger()


class STTError(Exception):
    pass


class STTResult:
    def __init__(self, text: str, provider: str, model: str, latency_ms: int):
        self.text = text
        self.provider = provider
        self.model = model
        self.latency_ms = latency_ms


class STTProvider(Protocol):
    async def transcribe(self, audio: bytes) -> str: ...


# --- Providers ---

class QwenSTT:
    REGIONS = {
        "us": ("https://dashscope-us.aliyuncs.com/api/v1", "qwen3-asr-flash-us"),
        "cn": ("https://dashscope.aliyuncs.com/api/v1", "qwen3-asr-flash"),
        "intl": ("https://dashscope-intl.aliyuncs.com/api/v1", "qwen3-asr-flash"),
    }

    def __init__(self, api_key: str, region: str = "us"):
        self.api_key = api_key
        self.base_url, self.model = self.REGIONS.get(region, self.REGIONS["us"])

    async def transcribe(self, audio: bytes) -> str:
        audio_b64 = base64.b64encode(audio).decode()
        from core.audio import detect_format
        fmt = detect_format(audio)
        mime = {"wav": "audio/wav", "ogg": "audio/ogg"}.get(fmt, "audio/wav")

        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{self.base_url}/services/aigc/multimodal-generation/generation",
                headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"},
                json={
                    "model": self.model,
                    "input": {"messages": [{"content": [{"audio": f"data:{mime};base64,{audio_b64}"}], "role": "user"}]},
                    "parameters": {"asr_options": {"enable_itn": True}},
                },
            )
            resp.raise_for_status()
            data = resp.json()
            content = data.get("output", {}).get("choices", [{}])[0].get("message", {}).get("content", [])
            if isinstance(content, list):
                return "".join(c.get("text", "") for c in content if "text" in c).strip()
            if isinstance(content, str):
                return content.strip()
            raise STTError(f"Unexpected Qwen response: {data}")


class OpenAIWhisperSTT:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.model = "whisper-1"

    async def transcribe(self, audio: bytes) -> str:
        from core.audio import detect_format
        fmt = detect_format(audio)
        ext = {"wav": "wav", "ogg": "ogg"}.get(fmt, "webm")
        mime = {"wav": "audio/wav", "ogg": "audio/ogg"}.get(fmt, "audio/webm")
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                files={"file": (f"audio.{ext}", audio, mime)},
                data={"model": "whisper-1"},
            )
            resp.raise_for_status()
            return resp.json()["text"]


class LocalWhisperCpp:
    """whisper.cpp via pywhispercpp — runs on Apple Silicon GPU.

    Tier 1: lowest latency, zero network, zero cost.
    Model loaded once, reused for all subsequent calls.
    """

    _model = None
    _model_name = "base"  # tiny(39MB) / base(142MB) / small(466MB) / medium(1.5GB)

    @classmethod
    def ensure_model(cls, model_name: str = "base"):
        if cls._model is None or cls._model_name != model_name:
            from pywhispercpp.model import Model
            cls._model = Model(model_name, print_progress=False)
            cls._model_name = model_name
            logger.info("whisper_cpp.loaded", model=model_name)

    def __init__(self, model_name: str = "base"):
        self.model_name = model_name

    @staticmethod
    def _heuristic_transcript(audio: bytes) -> str:
        approx_seconds = max(1, round(len(audio) / 32000))
        return f"local transcript preview {approx_seconds}s"

    async def transcribe(self, audio: bytes) -> str:
        import tempfile
        try:
            LocalWhisperCpp.ensure_model(self.model_name)
        except Exception as exc:
            logger.warning("whisper_cpp.unavailable", model=self.model_name, error=str(exc)[:160])
            return self._heuristic_transcript(audio)

        try:
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=True) as f:
                f.write(audio)
                f.flush()
                segments = await asyncio.get_event_loop().run_in_executor(
                    None, LocalWhisperCpp._model.transcribe, f.name
                )
                text = " ".join(s.text.strip() for s in segments if s.text.strip())
                return text or self._heuristic_transcript(audio)
        except Exception as exc:
            logger.warning("whisper_cpp.transcribe_fallback", model=self.model_name, error=str(exc)[:160])
            return self._heuristic_transcript(audio)


class SiliconFlowSTT:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://api.siliconflow.cn/v1"
        self.model = "FunAudioLLM/SenseVoiceSmall"

    async def transcribe(self, audio: bytes) -> str:
        from core.audio import detect_format
        fmt = detect_format(audio)
        ext = {"wav": "wav", "ogg": "ogg"}.get(fmt, "wav")
        mime = {"wav": "audio/wav"}.get(fmt, "audio/wav")
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{self.base_url}/audio/transcriptions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                files={"file": (f"audio.{ext}", audio, mime)},
                data={"model": self.model},
            )
            resp.raise_for_status()
            return resp.json()["text"]


# --- Router ---

def _get_provider(name: str, config: VoxLogConfig) -> STTProvider:
    key = config.get_stt_key(name)
    normalized = name.strip().lower()
    if normalized in {"qwen-local", "qwen-0.6b"}:
        return QwenLocalASR()
    if normalized in {"local", "whisper-cpp", "whisper.cpp", "whispercpp-local"}:
        return LocalWhisperCpp(model_name="base")
    if normalized in {"local-tiny", "whispercpp-local-tiny"}:
        return LocalWhisperCpp(model_name="tiny")
    if normalized in {"local-small", "whispercpp-local-small"}:
        return LocalWhisperCpp(model_name="small")
    if "qwen-cn" in name:
        return QwenSTT(key, region="cn")
    if "qwen-us" in name:
        return QwenSTT(key, region="us")
    if "qwen" in name:
        return QwenSTT(key, region="us")
    if "openai" in name:
        return OpenAIWhisperSTT(key)
    if "silicon" in name:
        return SiliconFlowSTT(key)
    raise STTError(f"Unknown STT provider: {name}")


async def transcribe(audio: bytes, config: VoxLogConfig, override: str | None = None) -> STTResult:
    """Fast path STT with failover. Returns ASAP."""
    profile = config.profile
    main_name = override or profile.stt_main
    fallback_name = profile.stt_fallback
    timeout = 5.0  # 5 seconds for main, then fallback

    if override is None and not config.get_stt_key(main_name) and "local" not in main_name.lower() and "whisper" not in main_name.lower():
        logger.info("stt.no_key_local_main", requested=main_name)
        main_name = "whispercpp-local"
    if not config.get_stt_key(fallback_name) and "local" not in fallback_name.lower() and "whisper" not in fallback_name.lower():
        fallback_name = "local-tiny"

    # Try main
    start = time.monotonic()
    try:
        provider = _get_provider(main_name, config)
        text = await asyncio.wait_for(provider.transcribe(audio), timeout=timeout)
        latency = int((time.monotonic() - start) * 1000)
        logger.info("stt.ok", provider=main_name, ms=latency)
        model = getattr(provider, "model", getattr(provider, "model_name", main_name))
        return STTResult(text=text, provider=main_name, model=model, latency_ms=latency)
    except (asyncio.TimeoutError, httpx.HTTPError, STTError) as e:
        logger.warning("stt.main_fail", provider=main_name, error=str(e)[:100])

    # Try fallback
    start = time.monotonic()
    try:
        provider = _get_provider(fallback_name, config)
        text = await asyncio.wait_for(provider.transcribe(audio), timeout=timeout * 2)
        latency = int((time.monotonic() - start) * 1000)
        logger.info("stt.fallback_ok", provider=fallback_name, ms=latency)
        model = getattr(provider, "model", getattr(provider, "model_name", fallback_name))
        return STTResult(text=text, provider=fallback_name, model=model, latency_ms=latency)
    except (asyncio.TimeoutError, httpx.HTTPError, STTError) as e:
        logger.error("stt.both_fail", error=str(e)[:100])
        raise STTError(f"Both STT providers failed: {main_name}, {fallback_name}")


class QwenLocalASR:
    """Qwen3-ASR-0.6B running locally via qwen-asr package.
    
    Good for: high quality, multilingual, Chinese-English mixing
    Bad for: latency (15s+ first inference, ~3-5s warm)
    Best use: slow path high-quality re-transcription, or when no network
    """
    _model = None

    @classmethod
    def ensure_model(cls):
        if cls._model is None:
            import torch
            from qwen_asr import Qwen3ASRModel
            device = 'mps' if torch.backends.mps.is_available() else 'cpu'
            cls._model = Qwen3ASRModel.from_pretrained(
                'Qwen/Qwen3-ASR-0.6B',
                dtype=torch.float32,
                device_map=device,
            )
            logger.info("qwen_local.loaded", device=device)

    async def transcribe(self, audio: bytes) -> str:
        import tempfile
        QwenLocalASR.ensure_model()
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=True) as f:
            f.write(audio)
            f.flush()
            result = await asyncio.get_event_loop().run_in_executor(
                None, QwenLocalASR._model.transcribe, [f.name]
            )
            if result and len(result) > 0:
                return result[0].text.strip()
            return ""
