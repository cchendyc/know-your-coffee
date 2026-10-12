"""SellerWorkload: counts of work waiting on a seller, per shop.

Three grouped count queries cover any number of shops, so the hub's
per-shop badges and the all-shops total cost the same as one shop. The
three run in parallel worker threads: against a database in another
region each statement is a full round trip, and the hub waits on all
of them before it can paint a single row.
"""

import asyncio

from starlette.concurrency import run_in_threadpool

from ...models.enums import CANCELABLE_STATUSES, ListingStatus, ShipmentStatus

# Shipments the seller still has to hand to a carrier.
UNSHIPPED_STATUSES = (ShipmentStatus.LABEL_READY, ShipmentStatus.READY_FOR_DROPOFF)

ZERO_WORKLOAD = {"to_fulfill": 0, "to_ship": 0, "low_stock": 0}


async def workload_by_shop(repos, shop_ids: list[str]) -> dict[str, dict]:
    to_fulfill, to_ship, low_stock = await asyncio.gather(
        run_in_threadpool(repos.orders.count_for_shops, shop_ids, CANCELABLE_STATUSES),
        run_in_threadpool(repos.shipments.count_for_shops, shop_ids, UNSHIPPED_STATUSES),
        run_in_threadpool(repos.products.count_for_shops, shop_ids, ListingStatus.LOW_STOCK),
    )
    return {
        shop_id: {
            "to_fulfill": to_fulfill.get(shop_id, 0),
            "to_ship": to_ship.get(shop_id, 0),
            "low_stock": low_stock.get(shop_id, 0),
        }
        for shop_id in shop_ids
    }


def sum_workloads(workloads) -> dict:
    return {key: sum(w[key] for w in workloads) for key in ZERO_WORKLOAD}
