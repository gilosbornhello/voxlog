"""VoxLog v2 Desktop Server — Fast Path + Slow Path architecture.

Fast path: STT + correction → return immediately
Slow path: polish + archive + index (background)

Endpoints:
  POST /v1/voice       — fast path: audio → display_text (immediate)
  POST /v1/save        — save pasted text directly
  GET  /v1/history     — search/list by agent
  GET  /v1/agents      — list agents
  DELETE /v1/history/{id} — recall (2 min window)
  POST /v1/asr/switch  — switch ASR model
  GET  /v1/detect      — auto-detect network profile
  GET  /v1/dictionary  — get dictionary
  POST /v1/dictionary  — update dictionary
  GET  /v1/stats       — usage stats
  GET  /health         — health check
"""

from __future__ import annotations

import asyncio
import json
import time
from contextlib import asynccontextmanager
from pathlib import Path

import structlog
import uvicorn
from fastapi import Depends, FastAPI, File, Form, HTTPException, Header, Query, Request, UploadFile
from fastapi.responses import PlainTextResponse

from runtime.fastpath.corrector import Corrector
from runtime.fastpath.pipeline import fast_path
from runtime.fastpath.stt import STTError
from runtime.models.config import VoxLogConfig, get_config
from runtime.models.events import RecordingMode, VoiceEvent, ArchiveStatus, ExportStatus
from runtime.slowpath.polisher import Polisher
from runtime.slowpath.worker import enqueue, start_worker
from memory.sqlite_store import SQLiteStore

logger = structlog.get_logger()

# Singletons
_config: VoxLogConfig | None = None
_store: SQLiteStore | None = None
_corrector: Corrector | None = None
_polisher: Polisher | None = None
_stt_override: str | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _config, _store, _corrector, _polisher
    _config = get_config()
    _config.log_dir.mkdir(parents=True, exist_ok=True)

    # Store
    _store = SQLiteStore(_config.db_path)
    await _store.init()

    # Corrector (load three dictionary layers)
    _corrector = Corrector()
    dict_dir = _config.terms_dir
    personal = Path.home() / ".voxlog" / "terms.json"
    _corrector.load(
        dict_dir / "base.json",
        dict_dir / "technical.json",
        personal if personal.exists() else dict_dir.parent / "terms.json",
    )

    # Polisher
    _polisher = Polisher()

    # Auto-detect profile
    import os
    if not os.getenv("VOXLOG_ENV"):
        from runtime.routing.profiles import detect_profile
        await detect_profile(_config)

    # Start slow path worker
    await start_worker(_config, _store, _polisher)

    logger.info("server.started", port=_config.port, profile=_config.active_profile)
    yield

    await _store.close()
    logger.info("server.stopped")


app = FastAPI(title="VoxLog", version="2.0.0", lifespan=lifespan)


def verify_token(authorization: str | None = Header(None)) -> None:
    if not _config or not _config.api_token:
        return
    if not authorization:
        raise HTTPException(401, "Missing auth")
    if authorization.removeprefix("Bearer ").strip() != _config.api_token:
        raise HTTPException(401, "Invalid token")


@app.get("/health")
async def health():
    return {"status": "ok", "version": "2.0.0", "profile": _config.active_profile if _config else "unknown"}


# === FAST PATH ===

@app.post("/v1/voice")
async def voice_endpoint(
    audio: UploadFile = File(...),
    source: str = Form("desktop"),
    env: str = Form("auto"),
    agent: str = Form(""),
    target_app: str = Form(""),
    mode: str = Form("normal"),
    _auth: None = Depends(verify_token),
):
    assert _config and _corrector and _store

    audio_bytes = await audio.read()
    if len(audio_bytes) < 100:
        raise HTTPException(422, "Audio too short")

    # Validate WAV if applicable
    from core.audio import detect_format, validate_wav
    fmt = detect_format(audio_bytes)
    if fmt == "wav":
        valid, err = validate_wav(audio_bytes, max_seconds=_config.max_audio_seconds)
        if not valid and "too long" in err:
            raise HTTPException(413, err)

    recording_mode = RecordingMode(mode) if mode in ("normal", "private", "ephemeral") else RecordingMode.NORMAL

    try:
        result, event = await fast_path(
            audio_bytes, _config, _corrector,
            source=source, agent=agent, target_app=target_app,
            recording_mode=recording_mode, stt_override=_stt_override,
        )
    except STTError as e:
        raise HTTPException(502, str(e))

    # Enqueue for slow path (non-blocking)
    enqueue(event)

    return {
        "id": result.id,
        "raw_text": result.raw_text,
        "display_text": result.display_text,
        "polished_text": result.display_text,  # same as display for now, slow path updates later
        "stt_provider": result.stt_provider,
        "latency_ms": result.latency_ms,
        "target_app": target_app,
        "agent": agent,
        "env": _config.active_profile,
        "role": "me",
        "created_at": event.created_at.isoformat(),
    }


# === SAVE TEXT ===

@app.post("/v1/save")
async def save_endpoint(
    text: str = Form(...),
    source: str = Form("paste"),
    agent: str = Form(""),
    target_app: str = Form(""),
    _auth: None = Depends(verify_token),
):
    assert _config and _store
    event = VoiceEvent(
        source=source, env=_config.active_profile, agent=agent,
        target_app=target_app or source,
        raw_text=text, display_text=text, polished_text=text,
        archive_status=ArchiveStatus.RAW_ONLY,
        role="other",
    )
    enqueue(event)
    return {
        "id": event.id, "raw_text": text, "display_text": text,
        "polished_text": text, "latency_ms": 0, "role": "other",
        "created_at": event.created_at.isoformat(),
    }


# === HISTORY ===

@app.get("/v1/agents")
async def agents_endpoint(_auth: None = Depends(verify_token)):
    assert _store
    return await _store.list_agents()


@app.get("/v1/history/agent")
async def history_by_agent(agent: str = Query(...), limit: int = Query(200), _auth: None = Depends(verify_token)):
    assert _store
    return await _store.list_by_agent(agent, limit)


@app.get("/v1/history")
async def history_endpoint(
    q: str = Query(""), date: str = Query(""), limit: int = Query(50),
    _auth: None = Depends(verify_token),
):
    assert _store
    if q:
        return await _store.search(q, limit)
    return []


@app.delete("/v1/history/{record_id}")
async def delete_record(record_id: str, _auth: None = Depends(verify_token)):
    assert _store
    ok = await _store.delete_event(record_id)
    if not ok:
        raise HTTPException(403, "Cannot recall (>2 min or not found)")
    return {"deleted": record_id}


@app.get("/v1/history/export", response_class=PlainTextResponse)
async def export_endpoint(date: str = Query(...), _auth: None = Depends(verify_token)):
    assert _store
    return await _store.export_markdown(date)


@app.get("/v1/stats")
async def stats_endpoint(_auth: None = Depends(verify_token)):
    assert _store
    return {"count": await _store.count(), "profile": _config.active_profile if _config else ""}


# === ASR SWITCH ===

@app.post("/v1/asr/switch")
async def switch_asr(model: str = Form(...), _auth: None = Depends(verify_token)):
    global _stt_override
    if model == "auto":
        _stt_override = None
        from runtime.routing.profiles import detect_profile, invalidate_cache
        invalidate_cache()
        assert _config
        await detect_profile(_config)
    else:
        _stt_override = model
    return {"model": _stt_override or "auto", "profile": _config.active_profile if _config else ""}


@app.get("/v1/detect")
async def detect_endpoint(_auth: None = Depends(verify_token)):
    assert _config
    from runtime.routing.profiles import detect_profile, invalidate_cache
    invalidate_cache()
    profile = await detect_profile(_config)
    p = _config.profile
    return {
        "env": profile,
        "asr_override": _stt_override,
        "route": {
            "asr_main": p.stt_main, "asr_fallback": p.stt_fallback,
            "llm_main": p.llm_main, "llm_fallback": p.llm_fallback,
        },
    }


# === DICTIONARY ===

@app.get("/v1/dictionary")
async def get_dict(_auth: None = Depends(verify_token)):
    path = Path.home() / ".voxlog" / "terms.json"
    if not path.exists():
        assert _config
        path = _config.terms_dir.parent / "terms.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"corrections": {}, "preserve": []}


@app.post("/v1/dictionary")
async def update_dict(request: Request, _auth: None = Depends(verify_token)):
    body = await request.json()
    path = Path.home() / ".voxlog" / "terms.json"
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
    else:
        data = {"version": 1, "corrections": {}, "preserve": [], "format_rules": {"cn_en_space": True}}

    action = body.get("action")
    if action == "add":
        w, r = body.get("wrong", "").strip(), body.get("right", "").strip()
        if w and r:
            data["corrections"][w] = r
            if r not in data.get("preserve", []):
                data.setdefault("preserve", []).append(r)
    elif action == "delete":
        data["corrections"].pop(body.get("wrong", ""), None)

    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    # Reload corrector
    if _corrector:
        _corrector.corrections = data.get("corrections", {})
        _corrector.preserve = data.get("preserve", [])

    return data


# === MAIN ===

def main():
    config = get_config()
    structlog.configure(processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ])
    uvicorn.run("apps.desktop.server:app", host=config.host, port=config.port, log_level="info")


if __name__ == "__main__":
    main()
