"""Seller: the viewer across every shop they own.

Ownership is shops.owner_user_id, so one user may own many shops. This module
gives the hub one place to read all of them and the work outstanding across
them; per-shop screens keep using shopId arguments."""

import asyncio

from ariadne import ObjectType

from ...core.graphql import require_shop_owner, require_user
from ..services.workload import sum_workloads

seller = ObjectType("Seller")


def owned_shop_ids(info, shop_id: str | None) -> list[str]:
    """Scope for cross-shop seller queries: one shop the viewer owns, or all of them."""
    if shop_id is not None:
        require_shop_owner(info, shop_id)
        return [shop_id]
    user = require_user(info)
    return [str(s.id) for s in info.context["repos"].shops.list_owned(user["id"])]


@seller.field("workload")
async def resolve_seller_workload(seller_row, info):
    # Shares the batch with shops[].workload, so asking for both costs the
    # same three queries as asking for either.
    loader = info.context["loaders"].shop_workload
    workloads = await asyncio.gather(*(loader.load(str(s.id)) for s in seller_row["shops"]))
    return sum_workloads(workloads)
