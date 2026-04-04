"""Optional LLM enhancer for digest generation."""

from __future__ import annotations

import json

import httpx
import structlog

from runtime.models.config import VoxLogConfig

logger = structlog.get_logger()

ENHANCE_PROMPT = """You are a structured memory compiler for a voice workflow.

Return strict JSON with keys:
- summary: concise sentence under 220 chars
- intent: one of coding, planning, debugging, review, general
- suggested_tags: array of short tags
- mentioned_entities: array of entity strings

Keep the output faithful to the source text. Do not invent facts."""


class DigestEnhancer:
    async def enhance(self, digest: dict, source_text: str, config: VoxLogConfig) -> dict:
        payload = dict(digest)
        if not config.digest_enhancement_enabled:
            payload["enhanced"] = False
            payload["enhancer_provider"] = "heuristic"
            return payload
        provider = self._resolve_provider(config)
        if not provider:
            payload["enhanced"] = False
            payload["enhancer_provider"] = "heuristic"
            return payload

        try:
            if provider == "openai":
                result = await self._call_openai(source_text, config.openai_key)
            elif provider == "qwen":
                result = await self._call_qwen(source_text, config.dashscope_key_cn or config.dashscope_key_us)
            else:
                result = await self._call_ollama(source_text)

            payload["summary"] = result.get("summary") or payload["summary"]
            payload["intent"] = result.get("intent") or payload["intent"]
            payload["suggested_tags"] = result.get("suggested_tags") or payload["suggested_tags"]
            payload["mentioned_entities"] = result.get("mentioned_entities") or payload["mentioned_entities"]
            payload["enhanced"] = True
            payload["enhancer_provider"] = provider
            return payload
        except Exception as exc:
            logger.warning("digest.enhancer_fail", provider=provider, error=str(exc)[:160])
            payload["enhanced"] = False
            payload["enhancer_provider"] = "heuristic"
            return payload

    def _resolve_provider(self, config: VoxLogConfig) -> str:
        preferred = (config.digest_enhancement_provider or "auto").lower()
        if preferred not in {"", "auto"}:
            if preferred == "openai" and config.openai_key:
                return "openai"
            if preferred == "qwen" and (config.dashscope_key_cn or config.dashscope_key_us):
                return "qwen"
            if preferred == "ollama":
                return "ollama"
            return ""
        llm_name = config.profile.llm_main.lower()
        if "openai" in llm_name and config.openai_key:
            return "openai"
        if "qwen" in llm_name and (config.dashscope_key_cn or config.dashscope_key_us):
            return "qwen"
        if "ollama" in llm_name:
            return "ollama"
        return ""

    async def _call_openai(self, text: str, key: str) -> dict:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}"},
                json={
                    "model": "gpt-4o-mini",
                    "response_format": {"type": "json_object"},
                    "messages": [
                        {"role": "system", "content": ENHANCE_PROMPT},
                        {"role": "user", "content": text},
                    ],
                    "temperature": 0.1,
                    "max_tokens": 400,
                },
            )
            response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            return json.loads(content)

    async def _call_qwen(self, text: str, key: str) -> dict:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}"},
                json={
                    "model": "qwen-turbo",
                    "messages": [
                        {"role": "system", "content": ENHANCE_PROMPT},
                        {"role": "user", "content": text},
                    ],
                    "temperature": 0.1,
                    "max_tokens": 400,
                    "response_format": {"type": "json_object"},
                },
            )
            response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            return json.loads(content)

    async def _call_ollama(self, text: str) -> dict:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                "http://localhost:11434/api/chat",
                json={
                    "model": "qwen2.5:7b",
                    "messages": [
                        {"role": "system", "content": ENHANCE_PROMPT},
                        {"role": "user", "content": text},
                    ],
                    "stream": False,
                    "format": "json",
                    "options": {"temperature": 0.1},
                },
            )
            response.raise_for_status()
            content = response.json()["message"]["content"]
            return json.loads(content)
