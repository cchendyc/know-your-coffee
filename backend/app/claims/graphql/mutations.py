"""Claim mutations: applying for ownership, and support's verdicts."""

from ariadne import MutationType
from graphql import GraphQLError

from ...core.graphql import require_admin, require_user

mutation = MutationType()


@mutation.field("claimShop")
def resolve_claim_shop(_, info, shopId, note=None, application=None):
    user = require_user(info)
    repos = info.context["repos"]
    shop = repos.shops.get(shopId)
    if not shop:
        raise GraphQLError(f"Shop {shopId} not found")
    if str(shop.owner_user_id or "") == user["id"]:
        raise GraphQLError("You already own this shop.")
    if shop.owner_user_id:
        raise GraphQLError("This shop already has a verified owner. Contact an admin to dispute.")
    application = application or {}
    # Legacy clients send only the top-level note; empty strings count as absent.
    merged = {
        "business_role": application.get("businessRole") or None,
        "contact": application.get("contact") or None,
        "website": application.get("website") or None,
        "note": application.get("note") or note or None,
    }
    if not any(merged.values()):
        raise GraphQLError("Tell support how to verify you: a role, contact, link, or note.")
    return repos.claims.create(user["id"], shopId, merged)


@mutation.field("resolveClaim")
def resolve_resolve_claim(_, info, claimId, approve):
    require_admin(info)
    claim = info.context["repos"].claims.resolve(claimId, approve)
    if not claim:
        raise GraphQLError(f"Claim {claimId} not found or already resolved.")
    return claim
