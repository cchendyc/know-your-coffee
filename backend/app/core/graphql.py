"""Authorization guards and argument checks shared by every domain's resolvers."""

from graphql import GraphQLError

MAX_PAGE_SIZE = 100


def page_bounds(limit: int, offset: int) -> tuple[int, int]:
    if limit < 1 or offset < 0:
        raise GraphQLError("limit must be at least 1 and offset at least 0.")
    return min(limit, MAX_PAGE_SIZE), offset


def require_user(info) -> dict:
    user = info.context["user"]
    if not user:
        # Clients match on "Sign in" + "contribute" to detect a stale session.
        raise GraphQLError("Sign in to contribute.")
    return user


def is_admin(info, user: dict) -> bool:
    record = info.context["repos"].users.get(user["id"])
    return bool(record and record.role == "ADMIN")


def require_admin(info) -> dict:
    user = require_user(info)
    if not is_admin(info, user):
        raise GraphQLError("Admin access required.")
    return user


def require_shop_owner(info, shop_id: str) -> dict:
    """Seller-hub gate: the shop's verified owner, or an admin."""
    user = require_user(info)
    shop = info.context["repos"].shops.get(shop_id)
    if not shop:
        raise GraphQLError(f"Shop {shop_id} not found")
    if str(shop.owner_user_id or "") != user["id"] and not is_admin(info, user):
        raise GraphQLError("Only the verified owner can manage this shop.")
    return user
