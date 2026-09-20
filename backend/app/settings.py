import os
from pathlib import Path

from dotenv import load_dotenv

# backend/.env; real deployments set env vars directly.
load_dotenv(Path(__file__).resolve().parents[1] / ".env")

DATABASE_URL = os.getenv("DATABASE_URL")
GOOGLE_OAUTH_CLIENT_ID = os.getenv("GOOGLE_OAUTH_CLIENT_ID")
# Twilio for phone sign-in SMS. Unset = dev mode: the code comes back in the
# GraphQL response instead of a text. Do not deploy phone sign-in without these.
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID")
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN")
TWILIO_FROM_NUMBER = os.getenv("TWILIO_FROM_NUMBER")
# Sign in with Apple: identity tokens must be issued to the app's bundle id.
APPLE_BUNDLE_ID = os.getenv("APPLE_BUNDLE_ID", "com.knowyourcoffee.app")
# Resend for email sign-in codes. Unset = dev mode, same as Twilio above.
RESEND_API_KEY = os.getenv("RESEND_API_KEY")
# Must be a sender on a domain verified in Resend, e.g. "Know Your Coffee <signin@yourdomain.com>".
EMAIL_FROM = os.getenv("EMAIL_FROM")
# Return sign-in codes in the API response when no SMS/email provider is set.
# NEVER enable in production: anyone could sign in as any phone or email.
AUTH_DEV_CODES = os.getenv("AUTH_DEV_CODES") == "1"
# The iOS app signs in with its own OAuth client; its ID tokens carry a
# different audience. Optional: unset simply disables app sign-in.
GOOGLE_OAUTH_IOS_CLIENT_ID = os.getenv("GOOGLE_OAUTH_IOS_CLIENT_ID")
SESSION_SECRET = os.getenv("SESSION_SECRET")
GOOGLE_PLACES_API_KEY = os.getenv("GOOGLE_PLACES_API_KEY")
YELP_API_KEY = os.getenv("YELP_API_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
# Comma-separated emails granted ADMIN on sign-in; the only way to bootstrap an admin.
ADMIN_EMAILS = {e.strip().lower() for e in os.getenv("ADMIN_EMAILS", "").split(",") if e.strip()}
PORT = int(os.getenv("PORT", "4000"))
