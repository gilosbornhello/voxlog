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
from runtime.fastpath.recent import RecentUtteranceStore
from runtime.fastpath.stt import STTError
from integrations.ai_mate_memory import AIMateMemorySink
from integrations.obsidian import ObsidianSink
from runtime.models.config import VoxLogConfig, get_config
from runtime.models.events import (
    ArchiveStatus,
    ExportStatus,
    FastPathResult,
    FastPathStatus,
    OutputMode,
    RecordingMode,
    TargetRiskLevel,
    VoiceEvent,
)
from runtime.slowpath.polisher import Polisher
from runtime.slowpath.digester import DailyDigester, ProjectDigester, SessionDigester
from runtime.slowpath.enhancer import DigestEnhancer
from runtime.slowpath.worker import enqueue, start_worker
from memory.sqlite_store import SQLiteStore

logger = structlog.get_logger()

# Singletons
_config: VoxLogConfig | None = None
_store: SQLiteStore | None = None
_corrector: Corrector | None = None
_polisher: Polisher | None = None
_stt_override: str | None = None
_recent: RecentUtteranceStore | None = None
_session_digester = SessionDigester()
_daily_digester = DailyDigester()
_project_digester = ProjectDigester()
_digest_enhancer = DigestEnhancer()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _config, _store, _corrector, _polisher, _recent
    _config = get_config()
    _config.log_dir.mkdir(parents=True, exist_ok=True)

    # Store
    _store = SQLiteStore(_config.db_path)
    await _store.init()

    # Corrector (load three dictionary layers)
    _corrector = Corrector()
    dict_dir = _config.terms_dir
    personal = Path.home() / ".voxlog2" / "terms.json"
    _corrector.load(
        dict_dir / "base.json",
        dict_dir / "technical.json",
        personal if personal.exists() else dict_dir.parent / "terms.json",
    )

    # Polisher
    _polisher = Polisher()
    _recent = RecentUtteranceStore(ttl_seconds=30)

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


app = FastAPI(title="VoxLog2", version="2.0.0", lifespan=lifespan)


def verify_token(authorization: str | None = Header(None)) -> None:
    if not _config or not _config.api_token:
        return
    if not authorization:
        raise HTTPException(401, "Missing auth")
    if authorization.removeprefix("Bearer ").strip() != _config.api_token:
        raise HTTPException(401, "Invalid token")


def _terms_path() -> Path:
    path = Path.home() / ".voxlog2" / "terms.json"
    if path.exists():
        return path
    assert _config
    return _config.terms_dir.parent / "terms.json"


def _load_terms() -> dict:
    path = _terms_path()
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"version": 1, "corrections": {}, "preserve": [], "format_rules": {"cn_en_space": True}}


def _settings_payload() -> dict:
    assert _config
    return {
        "providers": {
            "dashscope_us": {"configured": bool(_config.dashscope_key_us)},
            "dashscope_cn": {"configured": bool(_config.dashscope_key_cn)},
            "openai": {"configured": bool(_config.openai_key)},
            "siliconflow": {"configured": bool(_config.siliconflow_key)},
        },
        "active_profile": _config.active_profile,
        "digest_enhancement_enabled": bool(_config.digest_enhancement_enabled),
        "digest_enhancement_provider": _config.digest_enhancement_provider,
        "profiles": [
            {
                "name": profile.name,
                "stt_main": profile.stt_main,
                "stt_fallback": profile.stt_fallback,
                "llm_main": profile.llm_main,
                "llm_fallback": profile.llm_fallback,
            }
            for profile in _config.profiles.values()
        ],
        "backend_auth_required": bool(_config.api_token),
    }


def _fastpath_response_payload(result: FastPathResult, event: VoiceEvent, *, agent: str, role: str) -> dict:
    return {
        "id": result.id,
        "status": result.status.value,
        "raw_text": result.raw_text,
        "display_text": result.display_text,
        "polished_text": result.display_text,
        "stt_provider": result.stt_provider,
        "stt_model": result.stt_model,
        "target_risk_level": result.target_risk_level.value,
        "should_autopaste": result.should_autopaste,
        "needs_review": result.needs_review,
        "confidence": result.confidence,
        "dictionary_applied": result.dictionary_applied,
        "latency_ms": result.latency_ms,
        "target_app": event.target_app,
        "session_id": event.session_id,
        "utterance_id": event.utterance_id,
        "output_id": event.output_id,
        "output_mode": event.output_mode.value,
        "archive_status": event.archive_status.value,
        "agent": agent,
        "env": _config.active_profile if _config else "home",
        "role": role,
        "created_at": event.created_at.isoformat(),
    }


def _provider_connectivity_payload() -> dict:
    assert _config
    profile = _config.profiles[_config.active_profile]
    configured = {
        "dashscope_us": bool(_config.dashscope_key_us),
        "dashscope_cn": bool(_config.dashscope_key_cn),
        "openai": bool(_config.openai_key),
        "siliconflow": bool(_config.siliconflow_key),
    }
    configured_count = sum(1 for value in configured.values() if value)

    checks: list[dict[str, str]] = [
        {
            "key": "backend",
            "label": "Backend Bridge",
            "status": "ok",
            "message": "TS service can reach the configured backend.",
        }
    ]

    if configured_count:
        checks.append(
            {
                "key": "providers",
                "label": "Provider Keys",
                "status": "ok",
                "message": f"{configured_count} provider key(s) configured.",
            }
        )
    else:
        checks.append(
            {
                "key": "providers",
                "label": "Provider Keys",
                "status": "fail",
                "message": "Add at least one provider key to enable cloud fallback.",
            }
        )

    preferred_provider = profile.stt_main
    preferred_ready = False
    provider_map = {
        "qwen-us": configured["dashscope_us"],
        "qwen-cn": configured["dashscope_cn"],
        "openai-whisper": configured["openai"],
        "siliconflow-whisper": configured["siliconflow"],
        "whispercpp-local": True,
    }
    for key, value in provider_map.items():
        if preferred_provider.startswith(key):
            preferred_ready = value
            break

    checks.append(
        {
            "key": "stt-profile",
            "label": "Active STT Profile",
            "status": "ok" if preferred_ready else "warn",
            "message": (
                f"Active profile '{_config.active_profile}' can use {preferred_provider}."
                if preferred_ready
                else f"Active profile '{_config.active_profile}' prefers {preferred_provider}; local fallback may be used."
            ),
        }
    )

    return {
        "ready": configured_count > 0,
        "active_profile": _config.active_profile,
        "recommended_stt_provider": preferred_provider,
        "backend_url_reachable": True,
        "configured_provider_count": configured_count,
        "checks": checks,
    }


async def _export_digest_markdown(scope: str, *, session_id: str = "", digest_date: str = "", project_key: str = "") -> str:
    digest = await _rebuild_digest(
        scope,
        session_id=session_id,
        digest_date=digest_date,
        project_key=project_key,
    )
    header = f"# {digest['digest_type']}"
    meta = []
    if digest.get("session_id"):
        meta.append(f"session_id: {digest['session_id']}")
    if digest.get("digest_date"):
        meta.append(f"date: {digest['digest_date']}")
    if digest.get("project_key"):
        meta.append(f"project: {digest['project_key']}")
    meta.append(f"enhancer: {digest.get('enhancer_provider', 'heuristic')}")
    tags = ", ".join(digest.get("suggested_tags", [])) or "(none)"
    entities = ", ".join(digest.get("mentioned_entities", [])) or "(none)"
    lines = [
        header,
        "",
        *meta,
        "",
        "## Summary",
        digest.get("summary", ""),
        "",
        "## Intent",
        digest.get("intent", ""),
        "",
        "## Suggested Tags",
        tags,
        "",
        "## Mentioned Entities",
        entities,
        "",
    ]
    return "\n".join(lines)


async def _rebuild_digest(scope: str, *, session_id: str = "", digest_date: str = "", project_key: str = "") -> dict:
    assert _store and _config
    if scope == "session":
        if not session_id:
            raise HTTPException(400, "session_id required")
        events = await _store.list_events_for_session(session_id)
        if not events:
            raise HTTPException(404, "No session events found")
        model = events[-1]
        digest = _session_digester.build(model)
        source_text = model.polished_text or model.display_text or model.raw_text
        digest = await _digest_enhancer.enhance(digest, source_text, _config)
        await _store.upsert_session_digest(
            session_id=digest["session_id"],
            source_event_id=digest["source_event_id"],
            summary=digest["summary"],
            intent=digest["intent"],
            suggested_tags=digest["suggested_tags"],
            mentioned_entities=digest["mentioned_entities"],
            enhanced=digest.get("enhanced", False),
            enhancer_provider=digest.get("enhancer_provider", "heuristic"),
        )
        return await _store.get_session_digest(session_id)
    if scope == "daily":
        if not digest_date:
            raise HTTPException(400, "date required")
        events = await _store.list_events_for_date(digest_date)
        if not events:
            raise HTTPException(404, "No daily events found")
        digest = _daily_digester.build(events, date_key=digest_date)
        source_text = "\n".join(
            (item.polished_text or item.display_text or item.raw_text).strip()
            for item in events
            if (item.polished_text or item.display_text or item.raw_text).strip()
        )
        digest = await _digest_enhancer.enhance(digest, source_text, _config)
        await _store.upsert_daily_digest(
            digest_date=digest["digest_date"],
            source_event_id=digest["source_event_id"],
            summary=digest["summary"],
            intent=digest["intent"],
            suggested_tags=digest["suggested_tags"],
            mentioned_entities=digest["mentioned_entities"],
            enhanced=digest.get("enhanced", False),
            enhancer_provider=digest.get("enhancer_provider", "heuristic"),
        )
        return await _store.get_daily_digest(digest_date)
    if scope == "project":
        project_value = project_key.strip().lower()
        if not project_value:
            raise HTTPException(400, "project_key required")
        events = await _store.list_events_for_project(project_value)
        if not events:
            raise HTTPException(404, "No project events found")
        digest = _project_digester.build(events, project_key=project_value)
        source_text = "\n".join(
            (item.polished_text or item.display_text or item.raw_text).strip()
            for item in events
            if (item.polished_text or item.display_text or item.raw_text).strip()
        )
        digest = await _digest_enhancer.enhance(digest, source_text, _config)
        await _store.upsert_project_digest(
            project_key=digest["project_key"],
            source_event_id=digest["source_event_id"],
            summary=digest["summary"],
            intent=digest["intent"],
            suggested_tags=digest["suggested_tags"],
            mentioned_entities=digest["mentioned_entities"],
            enhanced=digest.get("enhanced", False),
            enhancer_provider=digest.get("enhancer_provider", "heuristic"),
        )
        return await _store.get_project_digest(project_value)
    raise HTTPException(400, "Unknown digest scope")


def _write_terms(data: dict) -> dict:
    path = _terms_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    if _corrector:
        _corrector.corrections = data.get("corrections", {})
        _corrector.preserve = data.get("preserve", [])
        _corrector.cn_en_space = data.get("format_rules", {}).get("cn_en_space", True)
    return data


def _recent_payload(item) -> dict:
    return {
        "id": item.event.id,
        "utterance_id": item.event.utterance_id,
        "session_id": item.event.session_id,
        "output_id": item.event.output_id,
        "status": item.result.status.value,
        "raw_text": item.result.raw_text,
        "display_text": item.result.display_text,
        "target_app": item.event.target_app,
        "target_risk_level": item.event.target_risk_level.value,
        "recording_mode": item.event.recording_mode.value,
        "output_mode": item.event.output_mode.value,
        "archive_status": item.event.archive_status.value,
        "confidence": item.result.confidence,
        "stt_provider": item.result.stt_provider,
        "stt_model": item.result.stt_model,
        "dictionary_applied": item.result.dictionary_applied,
        "expires_at": int(item.expires_at * 1000),
    }


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
    session_id: str = Form(""),
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
            session_id=session_id,
            recording_mode=recording_mode, stt_override=_stt_override,
        )
    except STTError as e:
        raise HTTPException(502, str(e))

    # Enqueue for slow path (non-blocking)
    enqueue(event)
    _recent.put(result, event, audio_bytes)

    return _fastpath_response_payload(result, event, agent=agent, role="me")


@app.post("/v1/voice/text")
async def text_voice_endpoint(request: Request, _auth: None = Depends(verify_token)):
    assert _config and _corrector and _store and _recent
    body = await request.json()
    text = str(body.get("text", "")).strip()
    if not text:
        raise HTTPException(422, "text required")

    source = str(body.get("source", "gateway-text")).strip() or "gateway-text"
    agent = str(body.get("agent", "")).strip()
    target_app = str(body.get("target_app", "")).strip() or source
    session_id = str(body.get("session_id", "")).strip()
    role = str(body.get("role", "other")).strip() or "other"
    mode = str(body.get("mode", "normal")).strip().lower()
    recording_mode = RecordingMode(mode) if mode in ("normal", "private", "ephemeral") else RecordingMode.NORMAL

    started_at = time.monotonic()
    display_text, dictionary_applied = _corrector.correct_with_trace(text)
    latency_ms = int((time.monotonic() - started_at) * 1000)
    confidence = 0.98 if text else 0.0
    risk = TargetRiskLevel.HIGH if "terminal" in target_app.lower() else TargetRiskLevel.LOW
    should_autopaste = risk != TargetRiskLevel.HIGH
    result = FastPathResult(
        id="",
        status=FastPathStatus.OK,
        display_text=display_text,
        raw_text=text,
        stt_provider="gateway-text",
        stt_model="text-v1",
        target_app=target_app,
        target_risk_level=risk,
        should_autopaste=should_autopaste,
        needs_review=False,
        confidence=confidence,
        dictionary_applied=dictionary_applied,
        latency_ms=latency_ms,
    )
    event = VoiceEvent(
        source=source,
        env=_config.active_profile,
        agent=agent,
        target_app=target_app,
        target_risk_level=risk,
        raw_text=text,
        display_text=display_text,
        polished_text="",
        audio_duration_ms=0,
        stt_provider="gateway-text",
        stt_model="text-v1",
        latency_stt_ms=0,
        latency_total_fast_ms=latency_ms,
        recording_mode=recording_mode,
        output_mode=OutputMode.PASTE if should_autopaste else OutputMode.PREVIEW_ONLY,
        confidence=confidence,
        archive_status=ArchiveStatus.QUEUED,
        export_status=ExportStatus.PENDING if recording_mode == RecordingMode.NORMAL else ExportStatus.SKIP,
        session_id=session_id,
        role=role,
    )
    result.id = event.id
    enqueue(event)
    _recent.put(result, event, b"")
    return _fastpath_response_payload(result, event, agent=agent, role=role)


# === SAVE TEXT ===

@app.post("/v1/save")
async def save_endpoint(
    text: str = Form(...),
    source: str = Form("paste"),
    agent: str = Form(""),
    target_app: str = Form(""),
    session_id: str = Form(""),
    mode: str = Form("normal"),
    _auth: None = Depends(verify_token),
):
    assert _config and _store
    recording_mode = RecordingMode(mode) if mode in ("normal", "private", "ephemeral") else RecordingMode.NORMAL
    event = VoiceEvent(
        source=source, env=_config.active_profile, agent=agent,
        target_app=target_app or source,
        raw_text=text, display_text=text, polished_text=text,
        session_id=session_id,
        recording_mode=recording_mode,
        archive_status=ArchiveStatus.RAW_ONLY,
        export_status=ExportStatus.PENDING if recording_mode == RecordingMode.NORMAL else ExportStatus.SKIP,
        role="other",
    )
    enqueue(event)
    return {
        "id": event.id, "raw_text": text, "display_text": text,
        "polished_text": text, "latency_ms": 0, "role": "other",
        "session_id": event.session_id,
        "utterance_id": event.utterance_id,
        "output_id": event.output_id,
        "output_mode": event.output_mode.value,
        "archive_status": event.archive_status.value,
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


@app.get("/v1/digests/session")
async def session_digest_endpoint(
    session_id: str = Query(...),
    _auth: None = Depends(verify_token),
):
    assert _store
    digest = await _store.get_session_digest(session_id)
    if not digest:
        raise HTTPException(404, "Session digest not found")
    return digest


@app.get("/v1/digests/daily")
async def daily_digest_endpoint(
    date: str = Query(...),
    _auth: None = Depends(verify_token),
):
    assert _store
    digest = await _store.get_daily_digest(date)
    if not digest:
        raise HTTPException(404, "Daily digest not found")
    return digest


@app.get("/v1/digests/project")
async def project_digest_endpoint(
    project_key: str = Query(...),
    _auth: None = Depends(verify_token),
):
    assert _store
    digest = await _store.get_project_digest(project_key.strip().lower())
    if not digest:
        raise HTTPException(404, "Project digest not found")
    return digest


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
    return _load_terms()


@app.get("/v1/settings/providers")
async def get_provider_settings(_auth: None = Depends(verify_token)):
    return _settings_payload()


@app.get("/v1/settings/providers/test")
async def test_provider_settings(_auth: None = Depends(verify_token)):
    return _provider_connectivity_payload()


@app.post("/v1/settings/providers")
async def update_provider_settings(request: Request, _auth: None = Depends(verify_token)):
    assert _config
    body = await request.json()

    if "dashscope_key_us" in body and body["dashscope_key_us"] is not None:
        _config.dashscope_key_us = str(body["dashscope_key_us"]).strip()
    if "dashscope_key_cn" in body and body["dashscope_key_cn"] is not None:
        _config.dashscope_key_cn = str(body["dashscope_key_cn"]).strip()
    if "openai_key" in body and body["openai_key"] is not None:
        _config.openai_key = str(body["openai_key"]).strip()
    if "siliconflow_key" in body and body["siliconflow_key"] is not None:
        _config.siliconflow_key = str(body["siliconflow_key"]).strip()

    active_profile = str(body.get("active_profile", "")).strip()
    if active_profile:
        _config.switch_profile(active_profile)
    if "digest_enhancement_enabled" in body and body["digest_enhancement_enabled"] is not None:
        _config.digest_enhancement_enabled = bool(body["digest_enhancement_enabled"])
    if "digest_enhancement_provider" in body and body["digest_enhancement_provider"] is not None:
        _config.digest_enhancement_provider = str(body["digest_enhancement_provider"]).strip() or "auto"

    return _settings_payload()


@app.post("/v1/digests/rebuild")
async def rebuild_digest_endpoint(request: Request, _auth: None = Depends(verify_token)):
    body = await request.json()
    scope = str(body.get("scope", "")).strip().lower()
    return await _rebuild_digest(
        scope,
        session_id=str(body.get("session_id", "")).strip(),
        digest_date=str(body.get("date", "")).strip(),
        project_key=str(body.get("project_key", "")).strip(),
    )


@app.get("/v1/digests/export", response_class=PlainTextResponse)
async def export_digest_endpoint(
    scope: str = Query(...),
    session_id: str = Query(""),
    date: str = Query(""),
    project_key: str = Query(""),
    _auth: None = Depends(verify_token),
):
    return await _export_digest_markdown(
        scope.strip().lower(),
        session_id=session_id.strip(),
        digest_date=date.strip(),
        project_key=project_key.strip(),
    )


@app.post("/v1/integrations/obsidian/export")
async def export_obsidian_endpoint(request: Request, _auth: None = Depends(verify_token)):
    body = await request.json()
    scope = str(body.get("scope", "")).strip().lower()
    vault_dir = str(body.get("vault_dir", "")).strip()
    if not vault_dir:
        raise HTTPException(400, "vault_dir required")
    markdown = await _export_digest_markdown(
        scope,
        session_id=str(body.get("session_id", "")).strip(),
        digest_date=str(body.get("date", "")).strip(),
        project_key=str(body.get("project_key", "")).strip(),
    )
    sink = ObsidianSink(Path(vault_dir))
    result = sink.export_digest(
        scope=scope,
        content=markdown,
        session_id=str(body.get("session_id", "")).strip(),
        digest_date=str(body.get("date", "")).strip(),
        project_key=str(body.get("project_key", "")).strip(),
    )
    return {
        "ok": True,
        "vault_path": result.vault_path,
        "note_path": result.note_path,
        "bytes_written": result.bytes_written,
    }


@app.post("/v1/integrations/ai-mate-memory/export")
async def export_ai_mate_memory_endpoint(request: Request, _auth: None = Depends(verify_token)):
    body = await request.json()
    scope = str(body.get("scope", "")).strip().lower()
    base_dir = str(body.get("base_dir", "")).strip()
    if not base_dir:
        raise HTTPException(400, "base_dir required")
    session_id = str(body.get("session_id", "")).strip()
    digest_date = str(body.get("date", "")).strip()
    project_key = str(body.get("project_key", "")).strip()
    markdown = await _export_digest_markdown(
        scope,
        session_id=session_id,
        digest_date=digest_date,
        project_key=project_key,
    )
    sink = AIMateMemorySink(Path(base_dir))
    result = sink.export_digest(
        scope=scope,
        markdown=markdown,
        session_id=session_id,
        digest_date=digest_date,
        project_key=project_key,
    )
    return {
        "ok": True,
        "base_path": result.base_path,
        "record_path": result.record_path,
        "bytes_written": result.bytes_written,
    }


@app.post("/v1/dictionary")
async def update_dict(request: Request, _auth: None = Depends(verify_token)):
    body = await request.json()
    data = _load_terms()

    action = body.get("action")
    if action == "add":
        w, r = body.get("wrong", "").strip(), body.get("right", "").strip()
        if w and r:
            data["corrections"][w] = r
            if r not in data.get("preserve", []):
                data.setdefault("preserve", []).append(r)
    elif action == "delete":
        data["corrections"].pop(body.get("wrong", ""), None)

    return _write_terms(data)


# === RECENT UTTERANCE ===

@app.get("/v1/recent")
async def recent_endpoint(_auth: None = Depends(verify_token)):
    assert _recent
    item = _recent.latest()
    if not item:
        return {"recent": None}
    return {"recent": _recent_payload(item)}


@app.post("/v1/recent/retry")
async def retry_recent_endpoint(
    utterance_id: str = Form(...),
    provider: str = Form(""),
    _auth: None = Depends(verify_token),
):
    assert _recent and _config and _corrector
    item = _recent.get(utterance_id)
    if not item:
        raise HTTPException(404, "Recent utterance not found or expired")

    try:
        result, event = await fast_path(
            item.audio,
            _config,
            _corrector,
            source=item.event.source,
            agent=item.event.agent,
            target_app=item.event.target_app,
            session_id=item.event.session_id,
            recording_mode=item.event.recording_mode,
            stt_override=provider or None,
            role=item.event.role,
        )
    except STTError as e:
        raise HTTPException(502, str(e))

    enqueue(event)
    _recent.put(result, event, item.audio)
    payload = _recent_payload(_recent.latest())
    payload["retried_from"] = utterance_id
    return payload


@app.post("/v1/recent/mode")
async def recent_mode_endpoint(
    utterance_id: str = Form(...),
    mode: str = Form(...),
    _auth: None = Depends(verify_token),
):
    assert _recent and _store
    item = _recent.get(utterance_id)
    if not item:
        raise HTTPException(404, "Recent utterance not found or expired")
    if mode not in ("normal", "private", "ephemeral"):
        raise HTTPException(422, "Invalid mode")

    recording_mode = RecordingMode(mode)
    item.event.recording_mode = recording_mode
    item.event.export_status = ExportStatus.PENDING if recording_mode == RecordingMode.NORMAL else ExportStatus.SKIP
    await _store.update_mode(item.event.id, recording_mode)
    return {"utterance_id": utterance_id, "mode": recording_mode.value}


@app.post("/v1/recent/dictionary")
async def recent_dictionary_endpoint(
    utterance_id: str = Form(...),
    wrong: str = Form(...),
    right: str = Form(...),
    _auth: None = Depends(verify_token),
):
    assert _recent
    item = _recent.get(utterance_id)
    if not item:
        raise HTTPException(404, "Recent utterance not found or expired")

    wrong = wrong.strip()
    right = right.strip()
    if not wrong or not right:
        raise HTTPException(422, "Both wrong and right terms are required")

    data = _load_terms()
    data["corrections"][wrong] = right
    if right not in data.get("preserve", []):
        data.setdefault("preserve", []).append(right)
    _write_terms(data)
    return {"utterance_id": utterance_id, "wrong": wrong, "right": right, "dictionary": data}


@app.post("/v1/recent/dismiss")
async def recent_dismiss_endpoint(
    utterance_id: str = Form(...),
    _auth: None = Depends(verify_token),
):
    assert _recent
    ok = _recent.dismiss(utterance_id)
    if not ok:
        raise HTTPException(404, "Recent utterance not found or expired")
    return {"utterance_id": utterance_id, "dismissed": True}


# === OUTPUT ===

@app.post("/v1/output/undo")
async def output_undo_endpoint(
    output_id: str = Form(...),
    _auth: None = Depends(verify_token),
):
    assert _recent and _store
    item = _recent.get_by_output_id(output_id)
    if not item:
        raise HTTPException(404, "Output not found or expired")

    archive_recalled = False
    if item.event.recording_mode != RecordingMode.EPHEMERAL:
        archive_recalled = await _store.delete_event(item.event.id)

    return {
        "output_id": output_id,
        "utterance_id": item.event.utterance_id,
        "accepted": True,
        "archive_recalled": archive_recalled,
        "ui_undo_required": True,
        "mode": item.event.recording_mode.value,
    }


# === MAIN ===

def main():
    config = get_config()
    structlog.configure(processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ])
    uvicorn.run(app, host=config.host, port=config.port, log_level="info")


if __name__ == "__main__":
    main()
