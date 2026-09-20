"""Email delivery via the Resend API (free tier: 3,000/month)."""

import httpx

from .. import settings


def configured() -> bool:
    return bool(settings.RESEND_API_KEY and settings.EMAIL_FROM)


async def send_email(to: str, subject: str, text: str) -> None:
    async with httpx.AsyncClient() as client:
        res = await client.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {settings.RESEND_API_KEY}"},
            json={"from": settings.EMAIL_FROM, "to": [to], "subject": subject, "text": text},
        )
    if res.status_code >= 400:
        raise RuntimeError(f"Resend rejected the email ({res.status_code}): {res.text[:200]}")
