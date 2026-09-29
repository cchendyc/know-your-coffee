"""Field resolvers for ShopClaim."""

from ariadne import ObjectType

shop_claim = ObjectType("ShopClaim")


@shop_claim.field("shop")
def resolve_claim_shop(claim, info):
    user = info.context["user"]
    return info.context["repos"].shops.get(str(claim.shop_id), user["id"] if user else None)


@shop_claim.field("applicant")
def resolve_applicant(claim, _info):
    return claim.user


@shop_claim.field("applicantOwnedShops")
def resolve_applicant_owned_shops(claim, info):
    return info.context["repos"].shops.list_owned(str(claim.user_id)) if claim.user_id else []


@shop_claim.field("createdAt")
def resolve_created_at(claim, _info):
    return claim.created_at.isoformat()


@shop_claim.field("resolvedAt")
def resolve_resolved_at(claim, _info):
    return claim.resolved_at.isoformat() if claim.resolved_at else None
