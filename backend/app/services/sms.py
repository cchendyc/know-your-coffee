"""SMS delivery via the Twilio Messages API."""

import httpx

from .. import settings


def configured() -> bool:
    return bool(settings.TWILIO_ACCOUNT_SID and settings.TWILIO_AUTH_TOKEN and settings.TWILIO_FROM_NUMBER)


async def send_sms(to: str, body: str) -> None:
    url = f"https://api.twilio.com/2010-04-01/Accounts/{settings.TWILIO_ACCOUNT_SID}/Messages.json"
    async with httpx.AsyncClient() as client:
        res = await client.post(
            url,
            auth=(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN),
            data={"To": to, "From": settings.TWILIO_FROM_NUMBER, "Body": body},
        )
    if res.status_code >= 400:
        raise RuntimeError(f"Twilio rejected the SMS ({res.status_code}): {res.text[:200]}")
