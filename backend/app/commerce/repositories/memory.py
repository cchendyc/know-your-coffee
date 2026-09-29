"""In-memory commerce repositories, mirroring the Postgres behavior."""

from datetime import UTC, date, datetime, timedelta

from ... import models as m
from ...core.errors import OutOfStockError
from ...core.memory import MemoryStore
from ...models.enums import (
    CANCELABLE_STATUSES,
    SHIPMENT_TO_ORDER_STATUS,
    Fulfillment,
    OrderStatus,
    ShipmentStatus,
)


def _now() -> datetime:
    return datetime.now(UTC)


def _page(rows: list, limit: int, offset: int) -> tuple[list, int]:
    return rows[offset : offset + limit], len(rows)


class MemoryProductRepository:
    def __init__(self, store: MemoryStore):
        self._store = store

    def list(
        self, shop_id: str, include_inactive: bool = False, status: m.ListingStatus | None = None
    ) -> list[m.Product]:
        products = [
            p for p in self._store.products.values()
            if str(p.shop_id) == shop_id and (include_inactive or p.active) and (not status or p.status == status)
        ]
        return sorted(products, key=lambda p: p.created_at)

    def page(
        self, shop_id: str, status: m.ListingStatus | None, limit: int, offset: int
    ) -> tuple[list[m.Product], int]:
        products = self.list(shop_id, include_inactive=True, status=status)
        products.sort(key=lambda p: (p.created_at, int(p.id)))
        return _page(products, limit, offset)

    def status_counts(self, shop_id: str) -> dict[m.ListingStatus, int]:
        counts = dict.fromkeys(m.ListingStatus, 0)
        for p in self._store.products.values():
            if str(p.shop_id) == shop_id:
                counts[p.status] += 1
        return counts

    def count_for_shops(self, shop_ids: list[str], status: m.ListingStatus) -> int:
        wanted = set(shop_ids)
        return sum(1 for p in self._store.products.values() if str(p.shop_id) in wanted and p.status == status)

    def get(self, product_id: str) -> m.Product | None:
        return self._store.products.get(str(product_id))

    def create(self, shop_id: str, values: dict) -> m.Product:
        defaults = {"variant": None, "stock_qty": 0, "low_stock_threshold": 5, "active": True}
        product = m.Product(
            id=self._store.next_id(),
            shop_id=int(shop_id),
            created_at=_now(),
            updated_at=_now(),
            **{**defaults, **values},
        )
        self._store.products[str(product.id)] = product
        return product

    def update(self, product_id: str, changes: dict) -> m.Product | None:
        product = self._store.products.get(str(product_id))
        if not product:
            return None
        for column, value in changes.items():
            setattr(product, column, value)
        product.updated_at = _now()
        return product

    def delete(self, product_id: str) -> bool:
        self._store.product_photos.pop(str(product_id), None)
        return self._store.products.pop(str(product_id), None) is not None


class MemoryProductPhotoRepository:
    def __init__(self, store: MemoryStore):
        self._store = store

    def list(self, product_id: str) -> list[m.ProductPhoto]:
        return sorted(self._store.product_photos.get(str(product_id), []), key=lambda p: (p.position, p.id))

    def cover(self, product_id: str) -> m.ProductPhoto | None:
        photos = self.list(product_id)
        return photos[0] if photos else None

    def replace(self, product_id: str, items: list[dict]) -> list[m.ProductPhoto]:
        existing = {str(p.id): p for p in self._store.product_photos.get(str(product_id), [])}
        ordered = []
        for position, item in enumerate(items):
            if item.get("id") is not None:
                photo = existing.get(str(item["id"]))
                if not photo:
                    continue
                photo.position = position
            else:
                photo = m.ProductPhoto(
                    id=self._store.next_id(),
                    product_id=int(product_id),
                    position=position,
                    data=item["data"],
                    created_at=_now(),
                )
            ordered.append(photo)
        self._store.product_photos[str(product_id)] = ordered
        return ordered


class MemoryOrderRepository:
    def __init__(self, store: MemoryStore):
        self._store = store

    def create(
        self,
        shop_id: str,
        buyer_user_id: str,
        items: list[dict],
        total: float,
        fulfillment: Fulfillment,
    ) -> m.Order:
        store = self._store
        # Check every line before decrementing so a failure changes nothing.
        for item in items:
            product = store.products.get(str(item["productId"]))
            if not product or product.stock_qty < item["qty"]:
                raise OutOfStockError(item["name"])
        for item in items:
            product = store.products[str(item["productId"])]
            product.stock_qty -= item["qty"]
            product.updated_at = _now()
        store.order_seq += 1
        order = m.Order(
            id=store.next_id(),
            number=store.order_seq,
            shop_id=int(shop_id),
            buyer_user_id=int(buyer_user_id),
            buyer=store.users.get(str(buyer_user_id)),
            items=items,
            total=total,
            status=OrderStatus.PLACED,
            fulfillment=fulfillment,
            created_at=_now(),
        )
        store.orders[str(order.id)] = order
        if fulfillment is Fulfillment.SHIP:
            shipment = m.Shipment(
                id=store.next_id(),
                order_id=order.id,
                carrier=None,
                tracking=None,
                ship_by=(_now() + timedelta(days=2)).date(),
                status=ShipmentStatus.LABEL_READY,
                created_at=_now(),
                updated_at=_now(),
            )
            store.shipments[str(shipment.id)] = shipment
        return order

    def get(self, order_id: str) -> m.Order | None:
        return self._store.orders.get(str(order_id))

    def page_for_shops(
        self, shop_ids: list[str], status: OrderStatus | None, limit: int, offset: int
    ) -> tuple[list[m.Order], int]:
        wanted = set(shop_ids)
        orders = [
            o for o in self._store.orders.values()
            if str(o.shop_id) in wanted and (status is None or o.status == status)
        ]
        orders.sort(key=lambda o: (o.created_at, int(o.id)), reverse=True)
        return _page(orders, limit, offset)

    def count_for_shops(self, shop_ids: list[str], statuses: tuple[OrderStatus, ...]) -> int:
        wanted = set(shop_ids)
        return sum(1 for o in self._store.orders.values() if str(o.shop_id) in wanted and o.status in statuses)

    def list_purchases(self, buyer_user_id: str) -> list[m.Order]:
        orders = [o for o in self._store.orders.values() if str(o.buyer_user_id or "") == buyer_user_id]
        return sorted(orders, key=lambda o: o.created_at, reverse=True)

    def cancel(self, order_id: str) -> m.Order | None:
        store = self._store
        order = store.orders.get(str(order_id))
        if not order or order.status not in CANCELABLE_STATUSES:
            return None
        order.status = OrderStatus.CANCELED
        for item in order.items:
            product = store.products.get(str(item["productId"]))
            if product:
                product.stock_qty += item["qty"]
        store.shipments = {sid: s for sid, s in store.shipments.items() if str(s.order_id) != str(order_id)}
        return order

    def transition(self, order_id: str, from_status: OrderStatus, to_status: OrderStatus) -> m.Order | None:
        order = self._store.orders.get(str(order_id))
        if not order or order.status != from_status:
            return None
        order.status = to_status
        return order


class MemoryShipmentRepository:
    def __init__(self, store: MemoryStore):
        self._store = store

    def get(self, shipment_id: str) -> m.Shipment | None:
        return self._store.shipments.get(str(shipment_id))

    def for_order(self, order_id: str) -> m.Shipment | None:
        return next((s for s in self._store.shipments.values() if str(s.order_id) == str(order_id)), None)

    def page_for_shops(
        self, shop_ids: list[str], status: ShipmentStatus | None, limit: int, offset: int
    ) -> tuple[list[m.Shipment], int]:
        store = self._store
        wanted = set(shop_ids)
        shipments = [
            s for s in store.shipments.values()
            if (order := store.orders.get(str(s.order_id))) and str(order.shop_id) in wanted
            and (status is None or s.status == status)
        ]
        # Postgres order: ship_by asc nulls last, then newest first.
        shipments.sort(key=lambda s: (-s.created_at.timestamp(), -int(s.id)))
        shipments.sort(key=lambda s: s.ship_by or date.max)
        return _page(shipments, limit, offset)

    def count_for_shops(self, shop_ids: list[str], statuses: tuple[ShipmentStatus, ...]) -> int:
        store = self._store
        wanted = set(shop_ids)
        return sum(
            1
            for s in store.shipments.values()
            if s.status in statuses
            and (order := store.orders.get(str(s.order_id)))
            and str(order.shop_id) in wanted
        )

    def update(self, shipment_id: str, changes: dict) -> m.Shipment | None:
        shipment = self._store.shipments.get(str(shipment_id))
        if not shipment:
            return None
        for column, value in changes.items():
            setattr(shipment, column, value)
        shipment.updated_at = _now()
        order_status = SHIPMENT_TO_ORDER_STATUS.get(changes.get("status"))
        if order_status and (order := self._store.orders.get(str(shipment.order_id))):
            order.status = order_status
        return shipment
