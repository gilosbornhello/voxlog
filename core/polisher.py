"""LLM text polishing with graceful degradation.

Applies dictionary corrections first, then LLM polish.
If LLM times out or errors, returns dictionary-corrected text with polished=False.
"""

from __future__ import annotations

import asyncio
import time

import httpx
import structlog

from core.config import VoxLogConfig
from core.dictionary import Dictionary
from core.models import LLMProvider, PolishResult

logger = structlog.get_logger()

POLISH_SYSTEM_PROMPT = """你是一个语音转文字的后处理助手。你的任务是清理 ASR（语音识别）的原始输出。

规则：
1. 去掉口头禅和填充词（嗯、啊、那个、就是说、you know、um、uh）
2. 修正明显的语音识别错误
3. 保持原意不变，不要添加内容
4. 中英文之间加空格
5. 修正标点符号（全角中文标点）
6. 保持技术术语的原始拼写（如 FastAPI, SwiftUI, Claude Code）
7. 输出只包含清理后的文字，不要任何解释

示例：
输入：嗯那个把首页的pricing section啊放到hero下面就是说
输出：把首页的 pricing section 放到 hero 下面。"""


async def _call_qwen_turbo(text: str, api_key: str) -> str:
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": "qwen-turbo",
                "messages": [
                    {"role": "system", "content": POLISH_SYSTEM_PROMPT},
                    {"role": "user", "content": text},
                ],
                "temperature": 0.1,
                "max_tokens": 2000,
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()


async def _call_openai_gpt(text: str, api_key: str) -> str:
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": "gpt-4o-mini",
                "messages": [
                    {"role": "system", "content": POLISH_SYSTEM_PROMPT},
                    {"role": "user", "content": text},
                ],
                "temperature": 0.1,
                "max_tokens": 2000,
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()


async def _call_ollama(text: str) -> str:
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            "http://localhost:11434/api/chat",
            json={
                "model": "qwen2.5:7b",
                "messages": [
                    {"role": "system", "content": POLISH_SYSTEM_PROMPT},
                    {"role": "user", "content": text},
                ],
                "stream": False,
                "options": {"temperature": 0.1},
            },
        )
        resp.raise_for_status()
        return resp.json()["message"]["content"].strip()


async def _call_llm(text: str, provider: LLMProvider, config: VoxLogConfig) -> str:
    if provider == LLMProvider.QWEN_TURBO:
        return await _call_qwen_turbo(text, config.dashscope_api_key)
    elif provider == LLMProvider.OPENAI_GPT:
        return await _call_openai_gpt(text, config.openai_api_key)
    elif provider == LLMProvider.OLLAMA:
        return await _call_ollama(text)
    raise ValueError(f"Unknown LLM provider: {provider}")


async def polish(
    text: str,
    dictionary: Dictionary,
    config: VoxLogConfig,
) -> PolishResult:
    """Apply dictionary corrections, then LLM polish. Degrade gracefully."""
    if not text or not text.strip():
        return PolishResult(polished_text="", provider=LLMProvider.QWEN_TURBO, polished=False, latency_ms=0)

    # Step 1: Dictionary corrections (always runs, ~0ms)
    corrected = dictionary.apply(text)

    # Step 2: LLM polish (may fail/timeout)
    route = config.route
    main_provider = route.llm.main
    fallback_provider = route.llm.fallback
    timeout = route.llm.timeout_seconds

    # Try main LLM
    start = time.monotonic()
    try:
        polished = await asyncio.wait_for(_call_llm(corrected, main_provider, config), timeout=timeout)
        latency = int((time.monotonic() - start) * 1000)
        logger.info("polish.success", provider=main_provider.value, latency_ms=latency)
        return PolishResult(polished_text=polished, provider=main_provider, polished=True, latency_ms=latency)
    except (asyncio.TimeoutError, httpx.HTTPError) as e:
        logger.warning("polish.main_failed", provider=main_provider.value, error=str(e))

    # Try fallback LLM
    start = time.monotonic()
    try:
        polished = await asyncio.wait_for(_call_llm(corrected, fallback_provider, config), timeout=timeout * 2)
        latency = int((time.monotonic() - start) * 1000)
        logger.info("polish.fallback_success", provider=fallback_provider.value, latency_ms=latency)
        return PolishResult(polished_text=polished, provider=fallback_provider, polished=True, latency_ms=latency)
    except (asyncio.TimeoutError, httpx.HTTPError) as e:
        logger.warning("polish.both_failed", error=str(e))

    # Both failed — return dictionary-corrected text (not raw)
    latency = int((time.monotonic() - start) * 1000)
    logger.warning("polish.degraded", text_len=len(corrected))
    return PolishResult(
        polished_text=corrected,
        provider=main_provider,
        polished=False,
        latency_ms=latency,
    )
