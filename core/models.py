"""Pydantic data models for VoxLog."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum

from pydantic import BaseModel, Field


class Environment(str, Enum):
    HOME = "home"
    OFFICE = "office"


class ASRProvider(str, Enum):
    QWEN = "qwen"
    OPENAI_WHISPER = "openai_whisper"
    LOCAL_WHISPER = "local_whisper"


class LLMProvider(str, Enum):
    QWEN_TURBO = "qwen_turbo"
    OPENAI_GPT = "openai_gpt"
    OLLAMA = "ollama"


class TranscribeRequest(BaseModel):
    audio: bytes = Field(exclude=True)
    env: Environment = Environment.HOME


class PolishRequest(BaseModel):
    text: str
    env: Environment = Environment.HOME


class VoiceRequest(BaseModel):
    audio: bytes = Field(exclude=True)
    source: str = "macos"
    env: Environment = Environment.HOME
    target_app: str = ""


class TranscribeResult(BaseModel):
    raw_text: str
    provider: ASRProvider
    latency_ms: int


class PolishResult(BaseModel):
    polished_text: str
    provider: LLMProvider
    polished: bool = True
    latency_ms: int


class VoiceResult(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    raw_text: str
    polished_text: str
    asr_provider: ASRProvider
    llm_provider: LLMProvider | None = None
    polished: bool = True
    duration_seconds: float = 0.0
    latency_ms: int = 0
    target_app: str = ""
    env: Environment = Environment.HOME
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class ArchiveRecord(BaseModel):
    id: str
    raw_text: str
    polished_text: str
    asr_provider: str
    llm_provider: str | None = None
    polished: bool
    duration_seconds: float
    latency_ms: int
    target_app: str
    env: str
    created_at: datetime


class HealthResponse(BaseModel):
    status: str = "ok"
    version: str = "0.1.0"
