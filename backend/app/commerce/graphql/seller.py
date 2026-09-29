"""Seller: the viewer across every shop they own.

Ownership is shops.owner_user_id, so one user may own many shops. This module
gives the hub one place to read all of them and the work outstanding across
them; per-shop screens keep using shopId arguments."""

from ariadne import ObjectType

from ...core.graphql import require_shop_owner, require_user
from ...models.enums import CANCELABLE_STATUSES, ListingStatus, ShipmentStatus

seller = ObjectType("Seller")

# Shipments the seller still has to hand to a carrier.
UNSHIPPED_STATUSES = (ShipmentStatus.LABEL_READY, ShipmentStatus.READY_FOR_DROPOFF)


def workload(repos, shop_ids: list[str]) -> dict:
    """SellerWorkload for one shop or for a whole seller; three count queries."""
    return {
        "to_fulfill": repos.orders.count_for_shops(shop_ids, CANCELABLE_STATUSES),
        "to_ship": repos.shipments.count_for_shops(shop_ids, UNSHIPPED_STATUSES),
        "low_stock": repos.products.count_for_shops(shop_ids, ListingStatus.LOW_STOCK),
    }


def owned_shop_ids(info, shop_id: str | None) -> list[str]:
    """Scope for cross-shop seller queries: one shop the viewer owns, or all of them."""
    if shop_id is not None:
        require_shop_owner(info, shop_id)
        return [shop_id]
    user = require_user(info)
    return [str(s.id) for s in info.context["repos"].shops.list_owned(user["id"])]


@seller.field("workload")
def resolve_seller_workload(seller_row, info):
    return workload(info.context["repos"], [str(s.id) for s in seller_row["shops"]])
