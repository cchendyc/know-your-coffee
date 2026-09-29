"""Session queries."""

from ariadne import QueryType
from graphql import GraphQLError

query = QueryType()


@query.field("me")
@query.field("userNode")
def resolve_me(_, info):
    user = info.context["user"]
    if not user:
        # Web and iOS drop their cached login on a "Sign in" message. Anonymous
        # callers still get null.
        if info.context.get("stale_token"):
            raise GraphQLError("Sign in again; your session has expired.")
        return None
    # The session token predates fields like phone and role; prefer the stored record.
    return info.context["repos"].users.get(user["id"]) or user
