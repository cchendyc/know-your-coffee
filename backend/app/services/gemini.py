"""Gemini generateContent. A hot model often returns 503; try the next one."""

import asyncio

import httpx

from .. import settings

# Lite first. gemini-3.6-flash is frequently UNAVAILABLE under demand.
_MODELS = ("gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.1-flash-lite")
_OVERLOADED = {429, 500, 502, 503}


class GeminiError(Exception):
    pass


def _text(payload: dict) -> str | None:
    candidates = payload.get("candidates") or []
    parts = (candidates[0].get("content") or {}).get("parts") if candidates else None
    for part in parts or []:
        if part.get("thought"):
            continue
        text = part.get("text")
        if text:
            return text
    return None


async def generate_json(parts: list[dict], *, timeout: float) -> str:
    last = "no response"
    async with httpx.AsyncClient(timeout=timeout) as client:
        for index, model in enumerate(_MODELS):
            try:
                res = await client.post(
                    f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
                    headers={"content-type": "application/json", "x-goog-api-key": settings.GEMINI_API_KEY},
                    json={
                        "contents": [{"parts": parts}],
                        "generationConfig": {"response_mime_type": "application/json"},
                    },
                )
            except httpx.HTTPError as exc:
                last = str(exc)
                continue
            if res.status_code == 200:
                text = _text(res.json())
                if text:
                    return text
                last = "empty response"
                continue
            last = f"{res.status_code} {res.text}"
            if res.status_code not in _OVERLOADED:
                break
            if index + 1 < len(_MODELS):
                await asyncio.sleep(0.4)
    raise GeminiError(last)
