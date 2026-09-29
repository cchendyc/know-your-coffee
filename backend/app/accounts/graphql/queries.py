"""Session queries."""

from ariadne import QueryType

query = QueryType()


@query.field("me")
@query.field("userNode")
def resolve_me(_, info):
    user = info.context["user"]
    if not user:
        return None
    # The session token predates fields like phone and role; prefer the stored record.
    return info.context["repos"].users.get(user["id"]) or user
