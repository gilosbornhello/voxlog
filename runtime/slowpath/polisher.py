"""LLM polisher — runs in slow path only. Never blocks fast path."""

from __future__ import annotations

import httpx
import structlog

from runtime.models.config import VoxLogConfig

logger = structlog.get_logger()

POLISH_PROMPT = """你是一个语音转文字的后处理助手。清理 ASR 的原始输出。

规则：
1. 去掉口头禅（嗯、啊、那个、就是说、um、uh）
2. 修正明显的语音识别错误
3. 保持原意不变，不添加内容
4. 中英文之间加空格
5. 修正标点符号
6. 保持技术术语原始拼写
7. 只输出清理后的文字"""


class Polisher:
    async def polish(self, text: str, config: VoxLogConfig) -> str | None:
        if not text or not text.strip():
            return None

        profile = config.profile
        llm_name = profile.llm_main

        try:
            if "openai" in llm_name:
                return await self._call_openai(text, config.openai_key)
            elif "qwen" in llm_name:
                return await self._call_qwen(text, config.dashscope_key_cn or config.dashscope_key_us)
            elif "ollama" in llm_name:
                return await self._call_ollama(text)
        except Exception as e:
            logger.warning("polisher.fail", provider=llm_name, error=str(e)[:100])

        return None

    async def _call_openai(self, text: str, key: str) -> str:
        async with httpx.AsyncClient(timeout=15.0) as c:
            r = await c.post("https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}"},
                json={"model": "gpt-4o-mini", "messages": [
                    {"role": "system", "content": POLISH_PROMPT},
                    {"role": "user", "content": text},
                ], "temperature": 0.1, "max_tokens": 2000})
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"].strip()

    async def _call_qwen(self, text: str, key: str) -> str:
        async with httpx.AsyncClient(timeout=15.0) as c:
            r = await c.post("https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}"},
                json={"model": "qwen-turbo", "messages": [
                    {"role": "system", "content": POLISH_PROMPT},
                    {"role": "user", "content": text},
                ], "temperature": 0.1, "max_tokens": 2000})
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"].strip()

    async def _call_ollama(self, text: str) -> str:
        async with httpx.AsyncClient(timeout=30.0) as c:
            r = await c.post("http://localhost:11434/api/chat",
                json={"model": "qwen2.5:7b", "messages": [
                    {"role": "system", "content": POLISH_PROMPT},
                    {"role": "user", "content": text},
                ], "stream": False, "options": {"temperature": 0.1}})
            r.raise_for_status()
            return r.json()["message"]["content"].strip()
