"""FastAPI localhost server — thin wrapper around VoxLog core.

Endpoints:
  POST /v1/voice      — combo: ASR + dictionary + LLM polish + archive
  POST /v1/transcribe  — ASR only
  POST /v1/polish      — LLM polish only (text in, text out)
  GET  /v1/history     — search/list voice history
  GET  /health         — health check
"""

from __future__ import annotations

import time
from contextlib import asynccontextmanager

import structlog
import uvicorn
from fastapi import Depends, FastAPI, File, Form, HTTPException, Header, Query, UploadFile
from fastapi.responses import PlainTextResponse

from core.archive import Archive
from core.asr_router import ASRError, transcribe
from core.audio import get_duration_seconds, validate_wav
from core.config import VoxLogConfig, get_config
from core.dictionary import Dictionary
from core.models import (
    Environment,
    HealthResponse,
    PolishResult,
    TranscribeResult,
    VoiceResult,
)
from core.polisher import polish

logger = structlog.get_logger()

# Module-level singletons (initialized in lifespan)
_config: VoxLogConfig | None = None
_archive: Archive | None = None
_dictionary: Dictionary | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _config, _archive, _dictionary
    _config = get_config()
    _config.log_dir.mkdir(parents=True, exist_ok=True)

    _archive = Archive(_config.db_path)
    await _archive.init()

    _dictionary = Dictionary(_config.terms_path)
    logger.info("server.started", host=_config.host, port=_config.port, env=_config.env.value)

    yield

    if _archive:
        await _archive.close()
    logger.info("server.stopped")


app = FastAPI(title="VoxLog", version="0.1.0", lifespan=lifespan)


def verify_token(authorization: str | None = Header(None)) -> None:
    if not _config or not _config.api_token:
        return  # No token configured = no auth (dev mode)
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing authorization header")
    token = authorization.removeprefix("Bearer ").strip()
    if token != _config.api_token:
        raise HTTPException(status_code=401, detail="Invalid token")


@app.get("/health")
async def health() -> HealthResponse:
    return HealthResponse()


@app.post("/v1/voice")
async def voice_endpoint(
    audio: UploadFile = File(...),
    source: str = Form("macos"),
    env: str = Form("home"),
    target_app: str = Form(""),
    _auth: None = Depends(verify_token),
) -> VoiceResult:
    assert _config and _archive and _dictionary
    start = time.monotonic()

    # Read and validate audio
    audio_bytes = await audio.read()
    environment = Environment(env)

    valid, err = validate_wav(audio_bytes, max_seconds=_config.max_audio_seconds)
    if not valid:
        if "too long" in err:
            raise HTTPException(status_code=413, detail=err)
        raise HTTPException(status_code=422, detail=err)

    duration_seconds = get_duration_seconds(audio_bytes)

    # Temporarily switch env if different from config
    original_env = _config.env
    if environment != _config.env:
        _config.switch_env(environment)

    try:
        # ASR
        try:
            asr_result = await transcribe(audio_bytes, _config)
        except ASRError as e:
            raise HTTPException(status_code=502, detail=str(e))

        # Dictionary + LLM polish
        polish_result = await polish(asr_result.raw_text, _dictionary, _config)

        total_latency = int((time.monotonic() - start) * 1000)

        result = VoiceResult(
            raw_text=asr_result.raw_text,
            polished_text=polish_result.polished_text,
            asr_provider=asr_result.provider,
            llm_provider=polish_result.provider,
            polished=polish_result.polished,
            duration_seconds=duration_seconds,
            latency_ms=total_latency,
            target_app=target_app,
            env=environment,
        )

        # Archive (fire and forget — don't let archive failure block response)
        try:
            await _archive.save(result)
        except Exception as e:
            logger.error("archive.save_failed", error=str(e))

        return result

    finally:
        if _config.env != original_env:
            _config.switch_env(original_env)


@app.post("/v1/transcribe")
async def transcribe_endpoint(
    audio: UploadFile = File(...),
    env: str = Form("home"),
    _auth: None = Depends(verify_token),
) -> TranscribeResult:
    assert _config
    audio_bytes = await audio.read()

    valid, err = validate_wav(audio_bytes, max_seconds=_config.max_audio_seconds)
    if not valid:
        if "too long" in err:
            raise HTTPException(status_code=413, detail=err)
        raise HTTPException(status_code=422, detail=err)

    environment = Environment(env)
    original_env = _config.env
    if environment != _config.env:
        _config.switch_env(environment)

    try:
        try:
            return await transcribe(audio_bytes, _config)
        except ASRError as e:
            raise HTTPException(status_code=502, detail=str(e))
    finally:
        if _config.env != original_env:
            _config.switch_env(original_env)


@app.post("/v1/polish")
async def polish_endpoint(
    text: str = Form(...),
    env: str = Form("home"),
    _auth: None = Depends(verify_token),
) -> PolishResult:
    assert _config and _dictionary
    environment = Environment(env)
    original_env = _config.env
    if environment != _config.env:
        _config.switch_env(environment)

    try:
        return await polish(text, _dictionary, _config)
    finally:
        if _config.env != original_env:
            _config.switch_env(original_env)


@app.get("/v1/history")
async def history_endpoint(
    q: str = Query(default="", description="Search query"),
    date: str = Query(default="", description="Date filter YYYY-MM-DD"),
    limit: int = Query(default=50, le=200),
    _auth: None = Depends(verify_token),
):
    assert _archive
    if q:
        return await _archive.search(q, limit=limit)
    elif date:
        return await _archive.list_by_date(date, limit=limit)
    else:
        # Default: today's records
        from datetime import datetime, timezone
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        return await _archive.list_by_date(today, limit=limit)


@app.get("/v1/history/export", response_class=PlainTextResponse)
async def export_endpoint(
    date: str = Query(..., description="Date to export YYYY-MM-DD"),
    _auth: None = Depends(verify_token),
) -> str:
    assert _archive
    return await _archive.export_markdown(date)


@app.get("/v1/history/count")
async def count_endpoint(_auth: None = Depends(verify_token)) -> dict:
    assert _archive
    return {"count": await _archive.count()}


def main():
    config = get_config()
    structlog.configure(
        processors=[
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.JSONRenderer(),
        ],
    )
    uvicorn.run(
        "server.app:app",
        host=config.host,
        port=config.port,
        log_level="info",
    )


if __name__ == "__main__":
    main()
