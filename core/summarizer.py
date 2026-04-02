"""Daily voice log summarizer.

Uses LLM to generate a summary of the day's voice inputs.
Useful for daily reflection and Obsidian notes.
"""

from __future__ import annotations

import httpx
import structlog

from core.config import VoxLogConfig

logger = structlog.get_logger()

SUMMARY_PROMPT = """你是一个个人助手，负责整理用户一天的语音输入记录。

以下是用户今天说的所有话（按时间排序）。请生成一个简洁的每日总结：

1. **今天做了什么**（按主题分组，不是按时间）
2. **关键决策和想法**（如果有）
3. **待办事项**（从语音内容中提取的 action items）

规则：
- 用中文写
- 简洁，不要重复原文
- 如果内容主要是代码指令，归纳为"编程工作"并列出主要任务
- 如果有明确的决策或想法，单独列出

用户今天的语音记录：
---
{content}
---

请生成每日总结："""


async def summarize_day(records: list[dict], config: VoxLogConfig) -> str:
    if not records:
        return "今天没有语音记录。"

    # Build content from records
    lines = []
    for r in records:
        time_part = r["created_at"][11:19] if len(r["created_at"]) > 19 else r["created_at"]
        app = r.get("target_app", "")
        app_tag = f" [{app}]" if app else ""
        lines.append(f"{time_part}{app_tag}: {r['polished_text']}")

    content = "\n".join(lines)
    prompt = SUMMARY_PROMPT.format(content=content)

    # Use the current env's main LLM
    route = config.route
    provider = route.llm.main

    try:
        from core.polisher import _call_llm
        # Reuse polisher's LLM call but with custom prompt
        from core.models import LLMProvider
        if provider == LLMProvider.OPENAI_GPT:
            return await _call_openai_summary(prompt, config.openai_api_key)
        elif provider == LLMProvider.QWEN_TURBO:
            return await _call_qwen_summary(prompt, config.dashscope_api_key)
        else:
            return await _call_ollama_summary(prompt)
    except Exception as e:
        logger.error("summarize.failed", error=str(e))
        return f"总结生成失败: {e}"


async def _call_openai_summary(prompt: str, api_key: str) -> str:
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": "gpt-4o-mini",
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.3,
                "max_tokens": 2000,
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()


async def _call_qwen_summary(prompt: str, api_key: str) -> str:
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": "qwen-turbo",
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.3,
                "max_tokens": 2000,
            },
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()


async def _call_ollama_summary(prompt: str) -> str:
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.post(
            "http://localhost:11434/api/chat",
            json={
                "model": "qwen2.5:7b",
                "messages": [{"role": "user", "content": prompt}],
                "stream": False,
                "options": {"temperature": 0.3},
            },
        )
        resp.raise_for_status()
        return resp.json()["message"]["content"].strip()
