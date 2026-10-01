"""In-memory commerce repositories, mirroring the Postgres behavior."""

from datetime import UTC, date, datetime, timedelta

from ... import models as m
from ...core.errors import OutOfStockError
from ...core.memory import MemoryStore
from ...models.enums import (
    CANCELABLE_STATUSES,
    SHIPMENT_TO_ORDER_STATUS,
    AttributeSection,
    AttributeValueType,
    Fulfillment,
    OrderStatus,
    ShipmentStatus,
)


def _now() -> datetime:
    return datetime.now(UTC)


def _page(rows: list, limit: int, offset: int) -> tuple[list, int]:
    return rows[offset : offset + limit], len(rows)


# Mirrors the seed in migrations 0033 and 0038; keep in step when the taxonomy changes.
# (key, label, type, unit, options)
_ATTRIBUTES = {
    "weight_g": ("Weight", AttributeValueType.INT, "g", []),
    "form": ("Form", AttributeValueType.ENUM, None, ["WHOLE_BEAN", "GROUND"]),
    "grind": ("Grind", AttributeValueType.ENUM, None, ["ESPRESSO", "FILTER", "FRENCH_PRESS", "COLD_BREW"]),
    "roast_level": ("Roast level", AttributeValueType.ENUM, None, ["LIGHT", "MEDIUM", "MEDIUM_DARK", "DARK"]),
    "process": ("Process", AttributeValueType.ENUM, None, ["WASHED", "NATURAL", "HONEY", "ANAEROBIC", "OTHER"]),
    "origin_country": ("Origin", AttributeValueType.TEXT, None, []),
    "origin_region": ("Region", AttributeValueType.TEXT, None, []),
    "producer": ("Producer / lot", AttributeValueType.TEXT, None, []),
    "variety": ("Variety", AttributeValueType.TEXT, None, []),
    "tasting_notes": ("Tasting notes", AttributeValueType.TEXT_LIST, None, []),
    "roasted_to_order": ("Roasted to order", AttributeValueType.BOOL, None, []),
    "volume_ml": ("Volume", AttributeValueType.INT, "ml", []),
    "serve": ("Served", AttributeValueType.ENUM, None, ["HOT", "ICED", "BOTTLED"]),
    "caffeine": ("Caffeine", AttributeValueType.ENUM, None, ["REGULAR", "DECAF", "NONE"]),
    "brand": ("Brand", AttributeValueType.TEXT, None, []),
    "model": ("Model", AttributeValueType.TEXT, None, []),
    "condition": ("Condition", AttributeValueType.ENUM, None, ["NEW", "OPEN_BOX", "USED"]),
    "size": ("Size", AttributeValueType.TEXT, None, []),
    "color": ("Color", AttributeValueType.TEXT, None, []),
    "material": ("Material", AttributeValueType.TEXT, None, []),
}
# (slug, label, subtitle_template, [(key, required, in_subtitle)])
_CATEGORIES = [
    (
        "beans",
        "Beans",
        "{weight_g} {form} · {roast_level}",
        [
            ("weight_g", True, True), ("form", True, True), ("grind", False, False), ("roast_level", False, True),
            ("process", False, False), ("origin_country", False, False), ("origin_region", False, False),
            ("producer", False, False), ("variety", False, False), ("tasting_notes", False, False),
            ("roasted_to_order", False, False),
        ],
    ),
    ("drink", "Drink", "{volume_ml} {serve}", [("volume_ml", True, True), ("serve", True, True), ("caffeine", False, False)]),
    ("gear", "Gear", "{brand} {model} · {condition}", [("brand", False, True), ("model", False, True), ("condition", True, True)]),
    ("merch", "Merch", "{color} · {size}", [("size", False, True), ("color", False, True), ("material", False, False)]),
]
# FORMAT fields sit on the editor's size/form card; everything else is DETAILS.
_FORMAT_KEYS = {"weight_g", "form", "grind", "roasted_to_order", "volume_ml", "serve", "condition", "size", "color"}


class MemoryCategoryRepository:
    def __init__(self, store: MemoryStore):
        self._store = store
        if not store.categories:
            self._seed()

    def list(self) -> list[m.Category]:
        return [c for c in self._store.categories.values() if c.is_visible]

    def get(self, category_id: str) -> m.Category | None:
        return self._store.categories.get(str(category_id))

    def fields(self, category_id: str) -> list[m.CategoryField]:
        return self._store.category_fields.get(str(category_id), [])

    def _seed(self) -> None:
        store = self._store
        for position, (slug, label, template, links) in enumerate(_CATEGORIES):
            category = m.Category(
                id=store.next_id(), parent_id=None, slug=slug, label=label, position=position,
                is_visible=True, subtitle_template=template, created_at=_now(),
            )
            store.categories[str(category.id)] = category
            store.category_fields[str(category.id)] = [
                m.CategoryField(
                    key=key,
                    label=_ATTRIBUTES[key][0],
                    value_type=_ATTRIBUTES[key][1],
                    unit=_ATTRIBUTES[key][2],
                    help=None,
                    required=required,
                    show_in_subtitle=in_subtitle,
                    section=AttributeSection.FORMAT if key in _FORMAT_KEYS else AttributeSection.DETAILS,
                    options=[
                        m.ProductAttributeOption(
                            id=store.next_id(), attribute_id=0, value=value,
                            label=value.replace("_", " ").capitalize(), position=i, is_active=True,
                        )
                        for i, value in enumerate(_ATTRIBUTES[key][3])
                    ],
                )
                for key, required, in_subtitle in links
            ]


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
        defaults = {"description": None, "attributes": {}, "quantity": 0, "low_stock_threshold": 5, "active": True}
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

    def _with_items(self, order: m.Order | None) -> m.Order | None:
        if order:
            order.items = list(self._store.order_items.get(str(order.id), []))
        return order

    def _event(self, order_id: int, status: OrderStatus, actor_user_id: str | None, note: str | None = None) -> None:
        event = m.OrderEvent(
            id=self._store.next_id(), order_id=order_id, status=status,
            actor_user_id=int(actor_user_id) if actor_user_id else None, note=note, created_at=_now(),
        )
        self._store.order_events.setdefault(str(order_id), []).append(event)

    def create(
        self,
        shop_id: str,
        buyer_user_id: str,
        lines: list[dict],
        fulfillment: Fulfillment,
        *,
        subtotal_cents: int,
        shipping_cents: int,
        shipping_address_id: str | None,
        ships_within_days: int,
        pickup_code: str | None,
    ) -> m.Order:
        store = self._store
        # Check every line before decrementing so a failure changes nothing.
        for line in lines:
            product = store.products.get(str(line["product_id"]))
            if not product or product.quantity < line["quantity"]:
                raise OutOfStockError(line["name"])
        for line in lines:
            product = store.products[str(line["product_id"])]
            product.quantity -= line["quantity"]
            product.updated_at = _now()
        store.order_seq += 1
        order = m.Order(
            id=store.next_id(),
            number=store.order_seq,
            shop_id=int(shop_id),
            buyer_user_id=int(buyer_user_id),
            buyer=store.users.get(str(buyer_user_id)),
            status=OrderStatus.PLACED,
            fulfillment=fulfillment,
            subtotal_cents=subtotal_cents,
            shipping_cents=shipping_cents,
            total_cents=subtotal_cents + shipping_cents,
            currency="USD",
            shipping_address_id=int(shipping_address_id) if shipping_address_id else None,
            pickup_code=pickup_code,
            payment_id=None,
            cancelled_at=None,
            cancellation_reason=None,
            created_at=_now(),
            updated_at=_now(),
        )
        store.orders[str(order.id)] = order
        store.order_items[str(order.id)] = [
            m.OrderItem(id=store.next_id(), order_id=order.id, shipment_id=None, created_at=_now(), **line)
            for line in lines
        ]
        self._event(order.id, OrderStatus.PLACED, buyer_user_id)
        if fulfillment is Fulfillment.SHIP:
            shipment = m.Shipment(
                id=store.next_id(),
                order_id=order.id,
                carrier=None,
                tracking=None,
                ship_by=(_now() + timedelta(days=ships_within_days)).date(),
                status=ShipmentStatus.LABEL_READY,
                label_url=None,
                cost_cents=None,
                tracking_status=None,
                dropped_off_at=None,
                delivered_at=None,
                created_at=_now(),
                updated_at=_now(),
            )
            store.shipments[str(shipment.id)] = shipment
        return self._with_items(order)

    def get(self, order_id: str) -> m.Order | None:
        return self._with_items(self._store.orders.get(str(order_id)))

    def events(self, order_id: str) -> list[m.OrderEvent]:
        return list(self._store.order_events.get(str(order_id), []))

    def page_for_shops(
        self, shop_ids: list[str], statuses: OrderStatus | tuple[OrderStatus, ...] | None, limit: int, offset: int
    ) -> tuple[list[m.Order], int]:
        if isinstance(statuses, OrderStatus):
            statuses = (statuses,)
        wanted = set(shop_ids)
        orders = [
            o for o in self._store.orders.values()
            if str(o.shop_id) in wanted and (not statuses or o.status in statuses)
        ]
        orders.sort(key=lambda o: (o.created_at, int(o.id)), reverse=True)
        rows, total = _page(orders, limit, offset)
        return [self._with_items(o) for o in rows], total

    def count_for_shops(self, shop_ids: list[str], statuses: tuple[OrderStatus, ...]) -> int:
        wanted = set(shop_ids)
        return sum(1 for o in self._store.orders.values() if str(o.shop_id) in wanted and o.status in statuses)

    def count_by_status(self, shop_ids: list[str]) -> dict[OrderStatus, int]:
        wanted = set(shop_ids)
        counts = dict.fromkeys(OrderStatus, 0)
        for o in self._store.orders.values():
            if str(o.shop_id) in wanted:
                counts[o.status] += 1
        return counts

    def list_purchases(self, buyer_user_id: str) -> list[m.Order]:
        orders = [o for o in self._store.orders.values() if str(o.buyer_user_id or "") == buyer_user_id]
        return [self._with_items(o) for o in sorted(orders, key=lambda o: o.created_at, reverse=True)]

    def cancel(self, order_id: str, actor_user_id: str | None = None, reason: str | None = None) -> m.Order | None:
        store = self._store
        order = store.orders.get(str(order_id))
        if not order or order.status not in CANCELABLE_STATUSES:
            return None
        order.status = OrderStatus.CANCELED
        order.cancelled_at = _now()
        order.cancellation_reason = reason
        order.updated_at = _now()
        for item in store.order_items.get(str(order_id), []):
            product = store.products.get(str(item.product_id))
            if product:
                product.quantity += item.quantity
        store.shipments = {sid: s for sid, s in store.shipments.items() if str(s.order_id) != str(order_id)}
        self._event(order.id, OrderStatus.CANCELED, actor_user_id, reason)
        return self._with_items(order)

    def transition(
        self,
        order_id: str,
        from_status: OrderStatus,
        to_status: OrderStatus,
        actor_user_id: str | None = None,
        shipment_changes: dict | None = None,
    ) -> m.Order | None:
        order = self._store.orders.get(str(order_id))
        if not order or order.status != from_status:
            return None
        order.status = to_status
        order.updated_at = _now()
        self._event(order.id, to_status, actor_user_id)
        shipment = next((s for s in self._store.shipments.values() if str(s.order_id) == str(order_id)), None)
        if shipment:
            for column, value in (shipment_changes or {}).items():
                setattr(shipment, column, value)
            shipment_status = ORDER_TO_SHIPMENT_STATUS.get(to_status)
            if shipment_status:
                shipment.status = shipment_status
                if shipment_status is ShipmentStatus.IN_TRANSIT:
                    shipment.dropped_off_at = _now()
                if shipment_status is ShipmentStatus.DELIVERED:
                    shipment.delivered_at = _now()
            shipment.updated_at = _now()
        return self._with_items(order)


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

    def update(self, shipment_id: str, changes: dict, actor_user_id: str | None = None) -> m.Shipment | None:
        shipment = self._store.shipments.get(str(shipment_id))
        if not shipment:
            return None
        for column, value in changes.items():
            setattr(shipment, column, value)
        shipment.updated_at = _now()
        if changes.get("status") is ShipmentStatus.IN_TRANSIT:
            shipment.dropped_off_at = _now()
        if changes.get("status") is ShipmentStatus.DELIVERED:
            shipment.delivered_at = _now()
        order_status = SHIPMENT_TO_ORDER_STATUS.get(changes.get("status"))
        order = self._store.orders.get(str(shipment.order_id))
        if order_status and order and order.status != order_status:
            order.status = order_status
            order.updated_at = _now()
            event = m.OrderEvent(
                id=self._store.next_id(), order_id=order.id, status=order_status,
                actor_user_id=int(actor_user_id) if actor_user_id else None, note=None, created_at=_now(),
            )
            self._store.order_events.setdefault(str(order.id), []).append(event)
        return shipment


class MemoryAddressRepository:
    def __init__(self, store: MemoryStore):
        self._store = store

    def get(self, address_id: str) -> m.Address | None:
        return self._store.addresses.get(str(address_id))

    def _live(self, user_id: str) -> list[m.Address]:
        return [a for a in self._store.addresses.values() if str(a.user_id) == str(user_id) and not a.deleted]

    def list_for_user(self, user_id: str) -> list[m.Address]:
        return sorted(self._live(user_id), key=lambda a: (not a.is_default, -a.created_at.timestamp()))

    def save(self, user_id: str, values: dict, replaces_id: str | None) -> m.Address:
        existing = self._live(user_id)
        replaced = next((a for a in existing if replaces_id and str(a.id) == str(replaces_id)), None)
        is_default = values.pop("is_default", None)
        if is_default is None:
            is_default = replaced.is_default if replaced else not existing
        if replaced:
            replaced.deleted = True
        if is_default:
            for other in existing:
                other.is_default = False
        defaults = {"line2": None, "phone": None, "country_code": "US"}
        row = m.Address(
            id=self._store.next_id(), user_id=int(user_id), is_default=is_default, deleted=False,
            created_at=_now(), **{**defaults, **values},
        )
        self._store.addresses[str(row.id)] = row
        return row

    def set_default(self, user_id: str, address_id: str) -> m.Address | None:
        rows = self._live(user_id)
        chosen = next((a for a in rows if str(a.id) == str(address_id)), None)
        if not chosen:
            return None
        for row in rows:
            row.is_default = row is chosen
        return chosen

    def delete(self, user_id: str, address_id: str) -> bool:
        row = self._store.addresses.get(str(address_id))
        if not row or str(row.user_id) != str(user_id) or row.deleted:
            return False
        row.deleted = True
        row.is_default = False
        return True
