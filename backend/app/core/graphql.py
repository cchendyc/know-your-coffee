"""Authorization guards and argument checks shared by every domain's resolvers."""

import functools

from graphql import GraphQLError
from starlette.concurrency import run_in_threadpool

MAX_PAGE_SIZE = 100


def threaded(resolver):
    """Run a sync resolver in a worker thread.

    Repositories block on psycopg. On the event loop that stalls every
    in-flight request, so one slow or stuck query reads as the API being
    down. Resolvers that only await httpx stay plain async; async resolvers
    that also hit a repository wrap that call in run_in_threadpool.
    """

    @functools.wraps(resolver)
    async def run_in_thread(*args, **kwargs):
        return await run_in_threadpool(resolver, *args, **kwargs)

    return run_in_thread


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


async def require_shop_owner_batched(info, shop_id: str) -> dict:
    """require_shop_owner for async resolvers. The shop row comes from the
    per-request loader, so a query that aliases one field per shop checks
    every shop with one statement."""
    user = require_user(info)
    shop = await info.context["loaders"].shop.load(shop_id)
    if not shop:
        raise GraphQLError(f"Shop {shop_id} not found")
    if str(shop.owner_user_id or "") != user["id"] and not await run_in_threadpool(is_admin, info, user):
        raise GraphQLError("Only the verified owner can manage this shop.")
    return user
