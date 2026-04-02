"""Environment-aware configuration for VoxLog.

Two network environments with different optimal ASR/LLM providers:
- Home (US exit via VPN router): Qwen ASR main + OpenAI Whisper fallback
- Office (China domestic): Qwen ASR domestic + local Whisper fallback
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

from core.models import ASRProvider, Environment, LLMProvider

VOXLOG_DIR = Path.home() / ".voxlog"
VOXLOG_DIR.mkdir(parents=True, exist_ok=True)

# Load .env from ~/.voxlog/.env
_env_path = VOXLOG_DIR / ".env"
if _env_path.exists():
    load_dotenv(_env_path)


@dataclass(frozen=True)
class ASRConfig:
    main: ASRProvider
    fallback: ASRProvider
    timeout_seconds: float = 3.0


@dataclass(frozen=True)
class LLMConfig:
    main: LLMProvider
    fallback: LLMProvider
    timeout_seconds: float = 5.0


@dataclass(frozen=True)
class EnvConfig:
    asr: ASRConfig
    llm: LLMConfig


# Route table: environment -> provider config
ROUTE_TABLE: dict[Environment, EnvConfig] = {
    Environment.HOME: EnvConfig(
        asr=ASRConfig(main=ASRProvider.QWEN, fallback=ASRProvider.OPENAI_WHISPER),
        llm=LLMConfig(main=LLMProvider.OPENAI_GPT, fallback=LLMProvider.QWEN_TURBO),
    ),
    Environment.OFFICE: EnvConfig(
        asr=ASRConfig(main=ASRProvider.QWEN, fallback=ASRProvider.OPENAI_WHISPER),
        llm=LLMConfig(main=LLMProvider.QWEN_TURBO, fallback=LLMProvider.OLLAMA),
    ),
}


@dataclass
class VoxLogConfig:
    env: Environment = field(
        default_factory=lambda: Environment(os.getenv("VOXLOG_ENV", "home"))
    )
    api_token: str = field(default_factory=lambda: os.getenv("VOXLOG_API_TOKEN", ""))
    dashscope_api_key: str = field(
        default_factory=lambda: os.getenv("DASHSCOPE_API_KEY", "")
    )
    openai_api_key: str = field(default_factory=lambda: os.getenv("OPENAI_API_KEY", ""))
    siliconflow_api_key: str = field(
        default_factory=lambda: os.getenv("SILICONFLOW_API_KEY", "")
    )
    db_path: Path = field(default_factory=lambda: VOXLOG_DIR / "history.db")
    terms_path: Path = field(
        default_factory=lambda: Path(__file__).parent.parent / "terms.json"
    )
    log_dir: Path = field(default_factory=lambda: VOXLOG_DIR / "logs")
    host: str = "127.0.0.1"
    port: int = 7890
    max_audio_seconds: int = 60

    @property
    def route(self) -> EnvConfig:
        return ROUTE_TABLE[self.env]

    def switch_env(self, env: Environment) -> None:
        object.__setattr__(self, "env", env)


def get_config() -> VoxLogConfig:
    return VoxLogConfig()
