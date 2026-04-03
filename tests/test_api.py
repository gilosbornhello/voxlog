"""Integration tests for server.app — FastAPI endpoints."""

import struct
from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from core.models import ASRProvider, LLMProvider, PolishResult, TranscribeResult


def _make_wav(seconds=3.0) -> bytes:
    sample_rate, channels, bits = 16000, 1, 16
    data_size = int(sample_rate * channels * (bits // 8) * seconds)
    header = bytearray(44)
    header[0:4] = b"RIFF"
    struct.pack_into("<I", header, 4, data_size + 36)
    header[8:12] = b"WAVE"
    header[12:16] = b"fmt "
    struct.pack_into("<I", header, 16, 16)
    struct.pack_into("<H", header, 20, 1)
    struct.pack_into("<H", header, 22, channels)
    struct.pack_into("<I", header, 24, sample_rate)
    struct.pack_into("<I", header, 28, sample_rate * channels * (bits // 8))
    struct.pack_into("<H", header, 32, channels * (bits // 8))
    struct.pack_into("<H", header, 34, bits)
    header[36:40] = b"data"
    struct.pack_into("<I", header, 40, data_size)
    return bytes(header) + b"\x00" * data_size


@pytest.fixture
def client():
    # Patch env to use temp DB and no auth
    import os
    import tempfile
    tmpdir = tempfile.mkdtemp()
    os.environ["VOXLOG_ENV"] = "home"
    os.environ["VOXLOG_API_TOKEN"] = ""  # No auth for tests
    os.environ.pop("DASHSCOPE_API_KEY", None)
    os.environ.pop("OPENAI_API_KEY", None)

    # Need to reimport to pick up env changes
    from server.app import app
    with TestClient(app) as c:
        yield c


class TestHealthEndpoint:
    def test_health(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["version"] == "0.1.0"


class TestVoiceEndpoint:
    def test_voice_happy_path(self, client):
        asr_result = TranscribeResult(raw_text="hello world", provider=ASRProvider.QWEN, latency_ms=500)
        polish_result = PolishResult(polished_text="Hello world.", provider=LLMProvider.QWEN_TURBO, polished=True, latency_ms=300)

        with (
            patch("server.app.transcribe", new_callable=AsyncMock, return_value=asr_result),
            patch("server.app.polish", new_callable=AsyncMock, return_value=polish_result),
        ):
            wav = _make_wav(seconds=3.0)
            resp = client.post(
                "/v1/voice",
                files={"audio": ("test.wav", wav, "audio/wav")},
                data={"source": "macos", "env": "home", "target_app": "Claude Code"},
            )
            assert resp.status_code == 200
            data = resp.json()
            assert data["raw_text"] == "hello world"
            assert data["polished_text"] == "Hello world."
            assert data["polished"] is True
            assert data["target_app"] == "Claude Code"

    def test_voice_audio_too_long(self, client):
        wav = _make_wav(seconds=605.0)  # over 600s limit
        resp = client.post(
            "/v1/voice",
            files={"audio": ("test.wav", wav, "audio/wav")},
            data={"source": "macos", "env": "home"},
        )
        assert resp.status_code == 413

    def test_voice_invalid_format(self, client):
        resp = client.post(
            "/v1/voice",
            files={"audio": ("test.ogg", b"OggS" + b"\x00" * 50, "audio/ogg")},
            data={"source": "macos", "env": "home"},
        )
        assert resp.status_code == 422

    def test_voice_asr_failure(self, client):
        from core.asr_router import ASRError
        with patch("server.app.transcribe", new_callable=AsyncMock, side_effect=ASRError("both failed")):
            wav = _make_wav()
            resp = client.post(
                "/v1/voice",
                files={"audio": ("test.wav", wav, "audio/wav")},
                data={"source": "macos", "env": "home"},
            )
            assert resp.status_code == 502


class TestTranscribeEndpoint:
    def test_transcribe_success(self, client):
        asr_result = TranscribeResult(raw_text="test", provider=ASRProvider.QWEN, latency_ms=400)
        with patch("server.app.transcribe", new_callable=AsyncMock, return_value=asr_result):
            wav = _make_wav()
            resp = client.post(
                "/v1/transcribe",
                files={"audio": ("test.wav", wav, "audio/wav")},
                data={"env": "home"},
            )
            assert resp.status_code == 200
            assert resp.json()["raw_text"] == "test"


class TestPolishEndpoint:
    def test_polish_success(self, client):
        polish_result = PolishResult(polished_text="Polished.", provider=LLMProvider.QWEN_TURBO, polished=True, latency_ms=200)
        with patch("server.app.polish", new_callable=AsyncMock, return_value=polish_result):
            resp = client.post(
                "/v1/polish",
                data={"text": "raw input", "env": "home"},
            )
            assert resp.status_code == 200
            assert resp.json()["polished_text"] == "Polished."


class TestHistoryEndpoint:
    def test_history_default(self, client):
        resp = client.get("/v1/history")
        assert resp.status_code == 200
        assert isinstance(resp.json(), list)

    def test_history_search(self, client):
        resp = client.get("/v1/history", params={"q": "test"})
        assert resp.status_code == 200

    def test_history_count(self, client):
        resp = client.get("/v1/history/count")
        assert resp.status_code == 200
        assert "count" in resp.json()


class TestAuth:
    def test_auth_required(self):
        import os
        import tempfile
        tmpdir = tempfile.mkdtemp()
        os.environ["VOXLOG_API_TOKEN"] = "secret-token"

        from importlib import reload
        import core.config
        reload(core.config)
        import server.app
        reload(server.app)

        with TestClient(server.app.app) as c:
            resp = c.post(
                "/v1/polish",
                data={"text": "test"},
            )
            assert resp.status_code == 401

        # Cleanup
        os.environ["VOXLOG_API_TOKEN"] = ""
        reload(core.config)
        reload(server.app)
