"""ASGI entry point. Run: uvicorn app.main:app --port 4000 --reload"""

from pathlib import Path

from ariadne import load_schema_from_path, make_executable_schema
from ariadne.asgi import GraphQL
from starlette.middleware.cors import CORSMiddleware

from .auth import verify_session_token
from .repository import create_repository
from .resolvers.mutations import mutation
from .resolvers.queries import coffee_shop, query, user_type

type_defs = load_schema_from_path(Path(__file__).resolve().parents[1] / "schema.graphql")
schema = make_executable_schema(type_defs, query, mutation, coffee_shop, user_type)

repo = create_repository()


def get_context(request, _data):
    header = request.headers.get("authorization") or ""
    token = header[7:] if header.startswith("Bearer ") else None
    return {"request": request, "repo": repo, "user": verify_session_token(token)}


app = CORSMiddleware(
    GraphQL(schema, context_value=get_context),
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
