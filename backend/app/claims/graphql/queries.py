"""Claim listing queries."""

from ariadne import QueryType

from ...core.graphql import require_admin

query = QueryType()


@query.field("myClaims")
def resolve_my_claims(_, info):
    user = info.context["user"]
    return info.context["repos"].claims.list(user_id=user["id"]) if user else []


@query.field("pendingClaims")
def resolve_pending_claims(_, info):
    require_admin(info)
    return info.context["repos"].claims.list(status="PENDING")
