"""Auto-detect network environment based on DNS resolution.

If google.com resolves fast (< 500ms) → home (US exit)
If google.com times out or slow → office (China domestic)

Falls back to manual VOXLOG_ENV setting if detection fails.
"""

from __future__ import annotations

import asyncio
import socket
import time

import structlog

from core.models import Environment

logger = structlog.get_logger()

# Cache the result for 5 minutes to avoid repeated DNS lookups
_cached_env: Environment | None = None
_cache_time: float = 0
_CACHE_TTL = 300  # 5 minutes


async def detect_environment() -> Environment:
    global _cached_env, _cache_time

    now = time.monotonic()
    if _cached_env and (now - _cache_time) < _CACHE_TTL:
        return _cached_env

    env = await _do_detect()
    _cached_env = env
    _cache_time = now
    logger.info("network.detected", env=env.value)
    return env


async def _do_detect() -> Environment:
    """Try to resolve google.com. Fast = US exit, slow/fail = China."""
    try:
        start = time.monotonic()
        # Run DNS resolution in thread pool (socket.getaddrinfo is blocking)
        await asyncio.wait_for(
            asyncio.get_event_loop().run_in_executor(
                None, socket.getaddrinfo, "google.com", 443
            ),
            timeout=1.0,
        )
        elapsed = (time.monotonic() - start) * 1000

        if elapsed < 500:
            logger.debug("network.dns_ok", host="google.com", ms=f"{elapsed:.0f}")
            return Environment.HOME  # Fast DNS = US exit
        else:
            logger.debug("network.dns_slow", host="google.com", ms=f"{elapsed:.0f}")
            return Environment.OFFICE  # Slow = probably China with partial access
    except (asyncio.TimeoutError, socket.gaierror, OSError):
        logger.debug("network.dns_failed", host="google.com")
        return Environment.OFFICE  # Can't reach google = China domestic


def invalidate_cache():
    """Force re-detection on next call."""
    global _cached_env, _cache_time
    _cached_env = None
    _cache_time = 0
