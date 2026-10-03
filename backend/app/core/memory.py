"""Shared state for the in-memory repositories (local dev without a database).

One store is shared by every memory repository so cross-domain cascades
(deleting a user anonymizes reports and reviews, deleting a shop drops its orders) see
the same data. Stores hold app.models instances that are never flushed, so
constructors must set every column explicitly (SQLAlchemy defaults only
apply on flush)."""

from dataclasses import dataclass, field
from itertools import count

from .. import models as m


@dataclass
class MemoryStore:
    shops: dict[str, m.Shop] = field(default_factory=dict)
    chains: dict[str, m.Chain] = field(default_factory=dict)
    reports: dict[str, list[m.Report]] = field(default_factory=dict)  # by shop id
    reviews: dict[str, list[m.Review]] = field(default_factory=dict)  # by shop id
    photos: dict[str, list[m.ShopPhoto]] = field(default_factory=dict)  # by shop id
    users: dict[str, m.User] = field(default_factory=dict)
    bookmarks: set = field(default_factory=set)  # (user_id, shop_id)
    visits: set = field(default_factory=set)  # (user_id, shop_id)
    claims: dict[str, m.ShopClaim] = field(default_factory=dict)
    login_codes: dict[str, dict] = field(default_factory=dict)
    categories: dict[str, m.Category] = field(default_factory=dict)
    category_fields: dict[str, list[m.CategoryField]] = field(default_factory=dict)  # by category id
    products: dict[str, m.Product] = field(default_factory=dict)
    product_photos: dict[str, list[m.ProductPhoto]] = field(default_factory=dict)  # by product id
    orders: dict[str, m.Order] = field(default_factory=dict)
    order_items: dict[str, list[m.OrderItem]] = field(default_factory=dict)  # by order id
    order_events: dict[str, list[m.OrderEvent]] = field(default_factory=dict)  # by order id
    shipments: dict[str, m.Shipment] = field(default_factory=dict)
    addresses: dict[str, m.Address] = field(default_factory=dict)
    order_seq: int = 1000
    _ids: count = field(default_factory=lambda: count(1))

    def next_id(self) -> int:
        return next(self._ids)
