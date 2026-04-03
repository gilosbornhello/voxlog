"""FastAPI localhost server — thin wrapper around VoxLog core.

Endpoints:
  POST /v1/voice      — combo: ASR + dictionary + LLM polish + archive
  POST /v1/transcribe  — ASR only
  POST /v1/polish      — LLM polish only (text in, text out)
  GET  /v1/history     — search/list voice history
  GET  /health         — health check
"""

from __future__ import annotations

import asyncio
import time
from contextlib import asynccontextmanager

import json
import structlog
import uvicorn
from fastapi import Depends, FastAPI, File, Form, HTTPException, Header, Query, Request, UploadFile
from fastapi.responses import PlainTextResponse
from pathlib import Path

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
_asr_override: str | None = None  # If set, overrides the route table ASR selection


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _config, _archive, _dictionary
    _config = get_config()
    _config.log_dir.mkdir(parents=True, exist_ok=True)

    _archive = Archive(_config.db_path)
    await _archive.init()

    _dictionary = Dictionary(_config.terms_path)

    # Auto-detect network environment if VOXLOG_ENV not explicitly set
    import os
    if not os.getenv("VOXLOG_ENV"):
        from core.network_detect import detect_environment
        detected = await detect_environment()
        _config.switch_env(detected)
        os.environ["DASHSCOPE_REGION"] = "cn" if detected == Environment.OFFICE else "us"
        logger.info("server.auto_env", env=detected.value, region=os.environ["DASHSCOPE_REGION"])

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
    agent: str = Form(""),
    _auth: None = Depends(verify_token),
) -> VoiceResult:
    assert _config and _archive and _dictionary
    start = time.monotonic()

    # Read audio
    audio_bytes = await audio.read()
    # Handle "auto" env — use current server config
    if env == "auto" or env not in ("home", "office"):
        environment = _config.env
    else:
        environment = _config.env if env in ("auto", "") else Environment(env)

    if len(audio_bytes) < 100:
        raise HTTPException(status_code=422, detail="Audio too short or empty")

    # Detect format and validate
    from core.audio import detect_format
    fmt = detect_format(audio_bytes)

    if fmt == "wav":
        valid, err = validate_wav(audio_bytes, max_seconds=_config.max_audio_seconds)
        if not valid:
            if "too long" in err:
                raise HTTPException(status_code=413, detail=err)
            raise HTTPException(status_code=422, detail=err)
        duration_seconds = get_duration_seconds(audio_bytes)
    else:
        # Non-WAV (WebM from browser, OGG from bot, etc.) — let ASR handle it
        duration_seconds = len(audio_bytes) / 32000  # rough estimate
        logger.info("audio.non_wav", format=fmt, size=len(audio_bytes))

    # Temporarily switch env if different from config
    original_env = _config.env
    if environment != _config.env:
        _config.switch_env(environment)

    try:
        # ASR (use override if set)
        try:
            asr_result = await transcribe(audio_bytes, _config, asr_override=_asr_override)
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
            agent=agent,
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

    environment = _config.env if env in ("auto", "") else Environment(env)
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
    environment = _config.env if env in ("auto", "") else Environment(env)
    original_env = _config.env
    if environment != _config.env:
        _config.switch_env(environment)

    try:
        return await polish(text, _dictionary, _config)
    finally:
        if _config.env != original_env:
            _config.switch_env(original_env)


@app.post("/v1/save")
async def save_text_endpoint(
    text: str = Form(...),
    source: str = Form("paste"),
    target_app: str = Form(""),
    agent: str = Form(""),
    _auth: None = Depends(verify_token),
) -> VoiceResult:
    """Save pasted text directly to archive. No ASR, no LLM. For recording AI responses."""
    assert _config and _archive
    from core.models import ASRProvider, LLMProvider

    result = VoiceResult(
        raw_text=text,
        polished_text=text,
        asr_provider=ASRProvider.QWEN,  # placeholder
        llm_provider=None,
        polished=False,
        duration_seconds=0.0,
        latency_ms=0,
        target_app=target_app or source,
        agent=agent,
        env=_config.env,
    )

    try:
        await _archive.save(result)
        logger.info("save.text", id=result.id, text_len=len(text), source=source)
    except Exception as e:
        logger.error("save.failed", error=str(e))

    return result


@app.get("/v1/agents")
async def agents_endpoint(_auth: None = Depends(verify_token)):
    """List all agents with message counts."""
    assert _archive
    return await _archive.list_agents()


@app.get("/v1/history/agent")
async def history_by_agent_endpoint(
    agent: str = Query(...),
    limit: int = Query(default=200, le=500),
    _auth: None = Depends(verify_token),
):
    assert _archive
    return await _archive.list_by_agent(agent, limit=limit)


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


@app.get("/v1/history/export/json", response_class=PlainTextResponse)
async def export_json_endpoint(
    date: str = Query(...), _auth: None = Depends(verify_token),
) -> str:
    from core.exporter import export_json
    assert _config
    return export_json(_config.db_path, date)


@app.get("/v1/history/export/csv", response_class=PlainTextResponse)
async def export_csv_endpoint(
    date: str = Query(...), _auth: None = Depends(verify_token),
) -> str:
    from core.exporter import export_csv
    assert _config
    return export_csv(_config.db_path, date)


@app.get("/v1/history/export/weekly", response_class=PlainTextResponse)
async def export_weekly_endpoint(
    end_date: str = Query(default="", description="End date YYYY-MM-DD, defaults to today"),
    _auth: None = Depends(verify_token),
) -> str:
    from core.exporter import export_weekly_summary
    assert _config
    if not end_date:
        from datetime import datetime, timezone
        end_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return export_weekly_summary(_config.db_path, end_date)


@app.get("/v1/history/count")
async def count_endpoint(_auth: None = Depends(verify_token)) -> dict:
    assert _archive
    return {"count": await _archive.count()}


@app.delete("/v1/history/{record_id}")
async def delete_record_endpoint(record_id: str, _auth: None = Depends(verify_token)) -> dict:
    """Delete a record (recall). Only works within 2 minutes of creation."""
    assert _archive and _archive._db
    # Check timestamp
    cursor = await _archive._db.execute(
        "SELECT created_at FROM voice_log WHERE id = ?", (record_id,)
    )
    row = await cursor.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Record not found")

    from datetime import datetime, timezone
    created = datetime.fromisoformat(row[0])
    now = datetime.now(timezone.utc)
    if (now - created).total_seconds() > 120:
        raise HTTPException(status_code=403, detail="Cannot recall after 2 minutes")

    await _archive._db.execute("DELETE FROM voice_log WHERE id = ?", (record_id,))
    await _archive._db.commit()
    logger.info("record.recalled", id=record_id)
    return {"deleted": record_id}


@app.get("/v1/stats")
async def stats_endpoint(_auth: None = Depends(verify_token)) -> dict:
    from core.stats import calculate_stats
    assert _config
    stats = calculate_stats(_config.db_path)
    return {
        "total_recordings": stats.total_recordings,
        "total_duration_min": round(stats.total_duration_min, 1),
        "today_recordings": stats.today_recordings,
        "today_duration_min": round(stats.today_duration_min, 1),
        "asr_breakdown": stats.asr_breakdown,
        "llm_breakdown": stats.llm_breakdown,
        "avg_latency_ms": round(stats.avg_latency_ms),
        "estimated_monthly_cost_cny": round(stats.estimated_monthly_cost_cny, 1),
    }


@app.post("/v1/env")
async def switch_env_endpoint(
    env: str = Form(...),
    _auth: None = Depends(verify_token),
) -> dict:
    assert _config
    new_env = Environment(env)
    _config.switch_env(new_env)
    logger.info("env.switched", env=new_env.value)
    return {"env": new_env.value, "route": {
        "asr_main": _config.route.asr.main.value,
        "asr_fallback": _config.route.asr.fallback.value,
        "llm_main": _config.route.llm.main.value,
        "llm_fallback": _config.route.llm.fallback.value,
    }}


@app.post("/v1/asr/switch")
async def switch_asr_endpoint(
    model: str = Form(...),
    _auth: None = Depends(verify_token),
) -> dict:
    """Switch ASR model. Model values: qwen-us, qwen-cn, openai, siliconflow, auto."""
    global _asr_override
    if model == "auto":
        _asr_override = None
        from core.network_detect import detect_environment, invalidate_cache
        invalidate_cache()
        detected = await detect_environment()
        assert _config
        _config.switch_env(detected)
        # Set region based on detected env
        import os
        os.environ["DASHSCOPE_REGION"] = "cn" if detected == Environment.OFFICE else "us"
        logger.info("asr.switch", model="auto", env=detected.value, region=os.environ["DASHSCOPE_REGION"])
    else:
        _asr_override = model
        logger.info("asr.switch", model=model)

    return {"model": _asr_override or "auto", "env": _config.env.value if _config else "unknown"}


@app.get("/v1/detect")
async def detect_env_endpoint(_auth: None = Depends(verify_token)) -> dict:
    """Auto-detect network environment and switch."""
    global _asr_override
    assert _config
    from core.network_detect import detect_environment, invalidate_cache
    invalidate_cache()
    detected = await detect_environment()
    _config.switch_env(detected)
    _asr_override = None  # Reset override on re-detect

    import os
    region = os.getenv("DASHSCOPE_REGION", "us")
    asr_main = _config.route.asr.main.value
    asr_detail = asr_main
    if asr_main == "qwen":
        asr_detail = f"qwen3-asr-flash-{region}" if region != "cn" else "qwen3-asr-flash"
    return {"env": detected.value, "asr_override": _asr_override, "route": {
        "asr_main": asr_detail,
        "asr_fallback": _config.route.asr.fallback.value,
        "llm_main": _config.route.llm.main.value,
        "llm_fallback": _config.route.llm.fallback.value,
    }}


@app.post("/v1/sync-obsidian")
async def sync_obsidian_endpoint(
    days: int = Query(default=7),
    _auth: None = Depends(verify_token),
) -> dict:
    from core.obsidian_sync import sync_recent
    assert _config
    exported = await asyncio.get_event_loop().run_in_executor(
        None, sync_recent, _config.db_path, days
    )
    return {"exported": len(exported), "files": exported}


@app.get("/v1/dictionary")
async def get_dictionary(_auth: None = Depends(verify_token)) -> dict:
    assert _config
    terms_path = _config.terms_path
    if terms_path.exists():
        return json.loads(terms_path.read_text(encoding="utf-8"))
    return {"corrections": {}, "preserve": [], "format_rules": {}}


@app.post("/v1/dictionary")
async def update_dictionary(request: Request, _auth: None = Depends(verify_token)) -> dict:
    assert _config and _dictionary
    body = await request.json()
    action = body.get("action")
    terms_path = _config.terms_path

    # Load current
    if terms_path.exists():
        data = json.loads(terms_path.read_text(encoding="utf-8"))
    else:
        data = {"version": 1, "corrections": {}, "preserve": [], "format_rules": {"cn_en_space": True, "punctuation": "zh-CN"}}

    if action == "add":
        wrong = body.get("wrong", "").strip()
        right = body.get("right", "").strip()
        if wrong and right:
            data["corrections"][wrong] = right
            if right not in data.get("preserve", []):
                data.setdefault("preserve", []).append(right)

    elif action == "delete":
        wrong = body.get("wrong", "").strip()
        data["corrections"].pop(wrong, None)

    # Save
    terms_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    # Reload dictionary in memory
    _dictionary.__init__(terms_path)

    logger.info("dictionary.updated", action=action, corrections=len(data["corrections"]))
    return data


@app.get("/v1/summary")
async def summary_endpoint(
    date: str = Query(default="", description="Date YYYY-MM-DD, defaults to today"),
    _auth: None = Depends(verify_token),
) -> dict:
    assert _archive and _config
    from core.summarizer import summarize_day
    if not date:
        from datetime import datetime, timezone
        date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    records = await _archive.list_by_date(date)
    record_dicts = [{"created_at": r.created_at.isoformat(), "polished_text": r.polished_text,
                     "target_app": r.target_app} for r in records]
    summary = await summarize_day(record_dicts, _config)
    return {"date": date, "record_count": len(records), "summary": summary}


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
