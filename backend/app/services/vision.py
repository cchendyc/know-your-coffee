"""Photo recognition via Gemini. Google Lens has no public API; Gemini's free
tier (aistudio.google.com) is the closest no-cost equivalent."""

import json
import re

import httpx
from graphql import GraphQLError

from .. import settings
from ..models import MACHINE_BRANDS, DrinkItem, MachineGuess

_GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent"
_DATA_URL_RE = re.compile(r"^data:(image/[a-z+]+);base64,(.*)$", re.S)


async def _gemini_vision(prompt: str, image_base64: str) -> str:
    match = _DATA_URL_RE.match(image_base64)
    mime_type = match.group(1) if match else "image/jpeg"
    data = match.group(2) if match else image_base64

    async with httpx.AsyncClient(timeout=60) as client:
        res = await client.post(
            _GEMINI_URL,
            headers={"content-type": "application/json", "x-goog-api-key": settings.GEMINI_API_KEY},
            json={
                "contents": [{"parts": [{"text": prompt}, {"inline_data": {"mime_type": mime_type, "data": data}}]}],
                "generationConfig": {"response_mime_type": "application/json"},
            },
        )
    if res.status_code != 200:
        raise GraphQLError(f"Gemini vision request failed: {res.status_code} {res.text}")
    candidates = res.json().get("candidates") or []
    parts = candidates[0]["content"]["parts"] if candidates else []
    text = parts[0].get("text") if parts else None
    if not text:
        raise GraphQLError("Gemini returned no answer for this photo.")
    return text


async def identify_machine(image_base64: str) -> MachineGuess:
    if not settings.GEMINI_API_KEY:
        return {
            "machine": "UNKNOWN",
            "machineModel": None,
            "confidence": 0.0,
            "notes": "Photo recognition is not configured yet (server is missing GEMINI_API_KEY). Enter the machine manually.",
        }

    text = await _gemini_vision(
        "Identify the espresso machine in this photo. Respond with JSON only: "
        f'{{"brand": one of {", ".join(MACHINE_BRANDS)}, "model": string or null, '
        '"confidence": number 0-1, "notes": short string}. Use UNKNOWN if no espresso machine is visible.',
        image_base64,
    )
    parsed = json.loads(text)
    brand = parsed.get("brand")
    return {
        "machine": brand if brand in MACHINE_BRANDS else "UNKNOWN",
        "machineModel": parsed.get("model"),
        "confidence": max(0.0, min(1.0, float(parsed.get("confidence") or 0))),
        "notes": parsed.get("notes"),
    }


async def parse_menu(image_base64: str) -> list[DrinkItem]:
    """Extracts drinks and prices from a user-uploaded menu photo."""
    if not settings.GEMINI_API_KEY:
        raise GraphQLError("Menu parsing is not configured yet (server is missing GEMINI_API_KEY). Enter drinks manually.")

    text = await _gemini_vision(
        "Extract all drinks from this cafe menu photo. Respond with JSON only: an array of "
        '{"name": string, "price": number or null}. Use the base/small size price in USD. '
        "Include specials. Return [] if this is not a menu.",
        image_base64,
    )
    parsed = json.loads(text)
    if not isinstance(parsed, list):
        return []
    drinks: list[DrinkItem] = []
    for item in parsed:
        name = item.get("name") if isinstance(item, dict) else None
        if not isinstance(name, str) or not name.strip():
            continue
        price = item.get("price")
        drinks.append({"name": name.strip(), "price": float(price) if isinstance(price, (int, float)) else None})
    return drinks
