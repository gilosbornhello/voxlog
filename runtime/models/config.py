"""VoxLog v2 configuration — profiles, providers, routing."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

VOXLOG_DIR = Path.home() / ".voxlog"
VOXLOG_DIR.mkdir(parents=True, exist_ok=True)

_env_path = VOXLOG_DIR / ".env"
if _env_path.exists():
    load_dotenv(_env_path)


@dataclass
class ProviderConfig:
    name: str
    api_key: str
    base_url: str = ""
    model: str = ""
    region: str = ""  # us, cn, any
    tier: str = ""    # local, cloud_cn, cloud_intl


@dataclass
class Profile:
    """Network environment profile with provider preferences."""
    name: str          # home, office, mobile
    stt_main: str      # provider name
    stt_fallback: str
    llm_main: str
    llm_fallback: str


@dataclass
class VoxLogConfig:
    # API keys
    dashscope_key_us: str = field(default_factory=lambda: os.getenv("DASHSCOPE_API_KEY", ""))
    dashscope_key_cn: str = field(default_factory=lambda: os.getenv("DASHSCOPE_API_KEY_CN", ""))
    openai_key: str = field(default_factory=lambda: os.getenv("OPENAI_API_KEY", ""))
    siliconflow_key: str = field(default_factory=lambda: os.getenv("SILICONFLOW_API_KEY", ""))

    # Server
    host: str = "127.0.0.1"
    port: int = 7890
    api_token: str = field(default_factory=lambda: os.getenv("VOXLOG_API_TOKEN", ""))

    # Paths
    db_path: Path = field(default_factory=lambda: VOXLOG_DIR / "history.db")
    terms_dir: Path = field(default_factory=lambda: Path(__file__).parent.parent.parent / "dictionaries")
    log_dir: Path = field(default_factory=lambda: VOXLOG_DIR / "logs")

    # Limits
    max_audio_seconds: int = 600  # 10 minutes

    # Active profile
    active_profile: str = "home"

    # Profiles
    profiles: dict[str, Profile] = field(default_factory=lambda: {
        "home": Profile(
            name="home",
            stt_main="qwen-us", stt_fallback="openai-whisper",
            llm_main="openai-gpt", llm_fallback="qwen-turbo",
        ),
        "office": Profile(
            name="office",
            stt_main="qwen-cn", stt_fallback="siliconflow",
            llm_main="qwen-turbo", llm_fallback="ollama",
        ),
    })

    @property
    def profile(self) -> Profile:
        return self.profiles.get(self.active_profile, self.profiles["home"])

    def switch_profile(self, name: str) -> None:
        if name in self.profiles:
            self.active_profile = name

    def get_stt_key(self, provider: str) -> str:
        if "qwen-cn" in provider:
            return self.dashscope_key_cn or self.dashscope_key_us
        if "qwen" in provider:
            return self.dashscope_key_us
        if "openai" in provider:
            return self.openai_key
        if "silicon" in provider:
            return self.siliconflow_key
        return ""


def get_config() -> VoxLogConfig:
    return VoxLogConfig()
