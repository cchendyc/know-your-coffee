"""Photo recognition via Gemini. Google Lens has no public API; Gemini's free
tier (aistudio.google.com) is the closest no-cost equivalent."""

import json
import re

from graphql import GraphQLError

from typing import TypedDict

from .. import settings
from ..models.enums import MACHINE_BRANDS
from .gemini import GeminiError, generate_json


# What machine a photo probably shows.
class MachineGuess(TypedDict):
    machine: str
    machine_model: str | None
    confidence: float
    notes: str | None


class DrinkItem(TypedDict):
    name: str
    price: float | None

_DATA_URL_RE = re.compile(r"^data:(image/[a-z+]+);base64,(.*)$", re.S)


async def _gemini_vision(prompt: str, image_base64: str) -> str:
    match = _DATA_URL_RE.match(image_base64)
    mime_type = match.group(1) if match else "image/jpeg"
    data = match.group(2) if match else image_base64

    try:
        return await generate_json(
            [{"text": prompt}, {"inline_data": {"mime_type": mime_type, "data": data}}],
            timeout=60,
        )
    except GeminiError as exc:
        raise GraphQLError(f"Gemini vision request failed: {exc}") from exc


async def identify_machine(image_base64: str) -> MachineGuess:
    if not settings.GEMINI_API_KEY:
        return {
            "machine": "UNKNOWN",
            "machine_model": None,
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
        "machine_model": parsed.get("model"),
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
