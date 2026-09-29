"""ASGI entry point. Run: uvicorn app.main:app --port 4000 --reload"""

from ariadne.asgi import GraphQL
from starlette.middleware.cors import CORSMiddleware

from .auth import verify_session_token
from .core.repositories import create_repositories
from .core.services import create_services
from .schema import create_schema

repos = create_repositories()
services = create_services(repos)


def get_context(request, _data):
    header = request.headers.get("authorization") or ""
    token = header[7:] if header.startswith("Bearer ") else None
    user = verify_session_token(token)
    return {
        "request": request,
        "repos": repos,
        "services": services,
        "user": user,
        # A token that fails verification (expired, or signed by another
        # secret) must be surfaced, or clients keep a cached login forever.
        "stale_token": bool(token) and user is None,
    }


app = CORSMiddleware(
    GraphQL(create_schema(), context_value=get_context),
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
