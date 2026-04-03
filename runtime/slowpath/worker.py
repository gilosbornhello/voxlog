"""Slow Path background worker — processes voice events asynchronously.

Runs after fast path returns. Failures here NEVER affect the user's input.

Jobs:
1. Archive raw event to SQLite
2. Optional LLM polish
3. Update search index
4. Queue for export
"""

from __future__ import annotations

import asyncio
import time
from collections import deque

import structlog

from runtime.models.config import VoxLogConfig
from runtime.models.events import ArchiveStatus, ExportStatus, RecordingMode, VoiceEvent

logger = structlog.get_logger()

# Background queue
_event_queue: deque[VoiceEvent] = deque(maxlen=1000)
_worker_task: asyncio.Task | None = None


def enqueue(event: VoiceEvent) -> None:
    """Add event to slow path queue. Non-blocking."""
    if event.recording_mode == RecordingMode.EPHEMERAL:
        logger.debug("slowpath.skip_ephemeral", id=event.id)
        return
    _event_queue.append(event)
    logger.debug("slowpath.enqueued", id=event.id, queue_size=len(_event_queue))


async def start_worker(config: VoxLogConfig, archive, polisher=None) -> None:
    """Start the background worker loop."""
    global _worker_task
    if _worker_task and not _worker_task.done():
        return
    _worker_task = asyncio.create_task(_worker_loop(config, archive, polisher))
    logger.info("slowpath.worker_started")


async def _worker_loop(config, archive, polisher):
    """Process events from queue forever."""
    while True:
        if _event_queue:
            event = _event_queue.popleft()
            try:
                await _process_event(event, config, archive, polisher)
            except Exception as e:
                logger.error("slowpath.process_fail", id=event.id, error=str(e)[:200])
        else:
            await asyncio.sleep(0.1)  # Poll every 100ms


async def _process_event(event: VoiceEvent, config, archive, polisher):
    """Process one event through the slow path."""
    start = time.monotonic()

    # Step 1: Archive raw event
    try:
        await archive.save_event(event)
        event.archive_status = ArchiveStatus.RAW_ONLY
        logger.debug("slowpath.archived", id=event.id)
    except Exception as e:
        event.archive_status = ArchiveStatus.FAILED
        logger.error("slowpath.archive_fail", id=event.id, error=str(e)[:100])
        return  # Don't proceed if archive fails

    # Step 2: Optional LLM polish (only for normal mode)
    if event.recording_mode == RecordingMode.NORMAL and polisher and event.raw_text:
        try:
            polished = await asyncio.wait_for(
                polisher.polish(event.raw_text, config),
                timeout=10.0,
            )
            if polished:
                event.polished_text = polished
                event.archive_status = ArchiveStatus.POLISHED
                await archive.update_polish(event.id, polished)
                logger.debug("slowpath.polished", id=event.id)
        except (asyncio.TimeoutError, Exception) as e:
            logger.warning("slowpath.polish_fail", id=event.id, error=str(e)[:100])
            # Polish failure is fine — raw text is preserved

    elapsed = int((time.monotonic() - start) * 1000)
    event.latency_total_slow_ms = elapsed
    logger.info("slowpath.done", id=event.id, ms=elapsed, status=event.archive_status.value)
