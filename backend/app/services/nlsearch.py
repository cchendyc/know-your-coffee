"""Natural-language search fallback. Lexical search runs first; when it
finds nothing, Gemini maps the query onto the structured shop filter."""

import json

import httpx

from .. import settings
from ..models import MACHINE_BRANDS

_GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent"

# Repeat queries are common (retyping, pagination); parsing is deterministic
# enough to memoize. Cleared wholesale when it grows past 256 entries.
_cache: dict[str, dict | None] = {}


async def parse_search(query: str) -> dict | None:
    """Returns {"machine", "city", "terms"} or None when parsing is
    unavailable or found nothing usable."""
    if not settings.GEMINI_API_KEY:
        return None
    key = query.strip().lower()
    if key in _cache:
        return _cache[key]

    brands = ", ".join(b for b in MACHINE_BRANDS if b != "UNKNOWN")
    prompt = (
        "Translate a coffee-shop search query into a structured filter. "
        'Respond with JSON only: {"machine": string or null, "city": string or null, '
        '"terms": array of strings}. '
        f"machine must be one of: {brands}. Only set it when the query names that espresso machine brand. "
        "city is a city name if the query mentions a place. "
        "terms are the words worth text-matching against shop data: roaster or coffee names, "
        "origin countries, varieties (e.g. Gesha), tasting notes, fermentation styles "
        "(e.g. anaerobic, koji), grinder brands, machine model names, milk brands, drink names. "
        "When the query asks for dog-friendliness, wifi, or outdoor seating, put the word "
        "'dog', 'wifi', or 'outdoor' in terms. No filler words. "
        f"Query: {json.dumps(query)}"
    )

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            res = await client.post(
                _GEMINI_URL,
                headers={"content-type": "application/json", "x-goog-api-key": settings.GEMINI_API_KEY},
                json={
                    "contents": [{"parts": [{"text": prompt}]}],
                    "generationConfig": {"response_mime_type": "application/json"},
                },
            )
        if res.status_code != 200:
            # Quota/outage is transient: skip the cache so recovery works.
            return None
        candidates = res.json().get("candidates") or []
        parts = candidates[0]["content"]["parts"] if candidates else []
        parsed = json.loads(parts[0]["text"]) if parts else {}
    except (httpx.HTTPError, KeyError, ValueError):
        # A broken fallback should never break search itself.
        return None

    machine = parsed.get("machine")
    result: dict | None = {
        "machine": machine if machine in MACHINE_BRANDS and machine != "UNKNOWN" else None,
        "city": parsed.get("city") or None,
        "terms": [t.strip() for t in parsed.get("terms") or [] if isinstance(t, str) and t.strip()],
    }
    if not (result["machine"] or result["city"] or result["terms"]):
        result = None

    if len(_cache) > 256:
        _cache.clear()
    _cache[key] = result
    return result
