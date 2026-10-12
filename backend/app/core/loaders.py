"""Per-request DataLoaders for the lookups GraphQL lists fan out into.

graphql-core resolves list items one by one, so a field like
CoffeeShop.products on a 1,000-shop page is 1,000 queries unless the
lookups are batched. Each loader collects the keys requested in one tick
of the event loop and runs a single IN (...) query in a worker thread.

Loaders live on the request context, never at module level: the cache
must not outlive the request, or every viewer would see the first
viewer's saved/been flags and stale rows.

Keys are str ids; repositories return dicts keyed the same way.
"""

from collections.abc import Awaitable, Callable

from aiodataloader import DataLoader
from starlette.concurrency import run_in_threadpool

from ..commerce.services.workload import ZERO_WORKLOAD, workload_by_shop
from ..models.enums import ListingStatus


class Loaders:
    def __init__(self, repos, viewer_id: str | None):
        self.shop = self._loader(lambda ids: repos.shops.get_many(ids, viewer_id))
        self.shop_products = self._loader(repos.products.list_for_shops, default=[])
        self.shop_review_summary = self._loader(repos.reviews.summary_for_shops, default=(0, None))
        self.shop_photo_count = self._loader(repos.photos.count_for_shops, default=0)
        self.shop_report_count = self._loader(repos.reports.count_for_shops, default=0)
        # Owner-only; the resolvers check ownership before loading.
        self.shop_workload = self._async_loader(lambda ids: workload_by_shop(repos, ids), default=ZERO_WORKLOAD)
        self.shop_product_status_counts = self._loader(
            repos.products.status_counts_for_shops, default=dict.fromkeys(ListingStatus, 0)
        )
        self.user = self._loader(repos.users.get_many)
        self.chain = self._loader(repos.chains.get_many)
        self.category = self._loader(repos.categories.get_many)
        self.category_fields = self._loader(repos.categories.fields_for_many, default=[])
        self.product_cover = self._loader(repos.product_photos.covers_for_products)
        self.order = self._loader(repos.orders.get_many)
        self.order_shipment = self._loader(repos.shipments.for_orders)
        # Only ever asked for the session user, so this loader exists to
        # merge savedCount and beenCount into one query, not to batch users.
        self.viewer_stats = self._loader(
            lambda ids: {user_id: repos.shops.viewer_stats(user_id) for user_id in ids}
        )

    @classmethod
    def _loader(cls, fetch: Callable[[list[str]], dict], default=None) -> DataLoader:
        """fetch is a blocking repository call; it runs in a worker thread."""
        return cls._async_loader(lambda keys: run_in_threadpool(fetch, keys), default)

    @staticmethod
    def _async_loader(fetch: Callable[[list[str]], Awaitable[dict]], default=None) -> DataLoader:
        """fetch is a coroutine function that does its own thread hopping."""

        async def batch(keys):
            found = await fetch(list(keys))
            return [found.get(key, default) for key in keys]

        return DataLoader(batch_load_fn=batch)
