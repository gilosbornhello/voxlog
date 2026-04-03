"""Voice event data model — the core schema for VoxLog v2.

Every voice input creates a VoiceEvent that flows through:
  Fast Path → immediate output
  Slow Path → background enrichment
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class RecordingMode(str, Enum):
    NORMAL = "normal"       # Archive + searchable + exportable
    PRIVATE = "private"     # Archive but hidden, no auto-export
    EPHEMERAL = "ephemeral" # No archive, instant output only


class SessionType(str, Enum):
    CODING = "coding"
    PLANNING = "planning"
    REVIEW = "review"
    JOURNAL = "journal"
    CHAT_WITH_AI = "chat_with_ai"
    GENERAL = "general"


class ArchiveStatus(str, Enum):
    PENDING = "pending"         # Fast path done, slow path not started
    RAW_ONLY = "raw_only"       # Archived without polish
    POLISHED = "polished"       # LLM polish complete
    FAILED = "failed"           # Slow path failed


class ExportStatus(str, Enum):
    PENDING = "pending"
    DONE = "done"
    FAILED = "failed"
    SKIP = "skip"              # Private/ephemeral mode


class VoiceEvent(BaseModel):
    """Core data model for every voice input."""
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    # Session
    session_id: str = ""
    session_type: SessionType = SessionType.GENERAL

    # Source
    source: str = "desktop"  # desktop | feishu | wecom | web
    env: str = "home"        # home | office | mobile
    agent: str = ""          # which agent this is addressed to

    # Target
    target_app: str = ""     # frontmost app name

    # Content — three versions
    raw_text: str = ""           # exact ASR output
    display_text: str = ""       # fast path: dictionary-corrected, used for paste
    polished_text: str = ""      # slow path: LLM enhanced (filled async)

    # Audio metadata
    audio_duration_ms: int = 0

    # Provider info
    stt_provider: str = ""
    llm_provider: str = ""

    # Latency
    latency_stt_ms: int = 0
    latency_total_fast_ms: int = 0
    latency_total_slow_ms: int = 0

    # Classification
    language_mix: str = "mixed"  # zh | en | mixed
    tags: list[str] = Field(default_factory=list)

    # Privacy
    recording_mode: RecordingMode = RecordingMode.NORMAL

    # Status
    archive_status: ArchiveStatus = ArchiveStatus.PENDING
    export_status: ExportStatus = ExportStatus.PENDING

    # Role in conversation
    role: str = "me"  # me | other


class FastPathResult(BaseModel):
    """What the fast path returns to the UI immediately."""
    id: str
    display_text: str
    raw_text: str
    stt_provider: str
    latency_ms: int


class SlowPathUpdate(BaseModel):
    """What the slow path produces asynchronously."""
    id: str
    polished_text: str = ""
    llm_provider: str = ""
    tags: list[str] = Field(default_factory=list)
    archive_status: ArchiveStatus = ArchiveStatus.RAW_ONLY
    latency_slow_ms: int = 0
