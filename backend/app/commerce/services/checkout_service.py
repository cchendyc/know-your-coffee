"""Checkout: cart validation, price snapshots, order creation."""

import secrets

from ... import models as m
from ...core.errors import CheckoutError
from ...models.enums import Fulfillment


class CheckoutService:
    def __init__(self, products, orders, listings):
        self._products = products
        self._orders = orders
        self._listings = listings

    def place_order(self, shop: m.Shop, buyer_id: str, items: list[dict], fulfillment: Fulfillment) -> m.Order:
        if fulfillment is Fulfillment.SHIP:
            offered, setting = shop.offers_shipping, "shipping"
        else:
            offered, setting = shop.offers_pickup, "pickup"
        if not offered:
            raise CheckoutError(f"{shop.name} does not offer {setting}.")
        if not items:
            raise CheckoutError("The cart is empty.")
        lines = []
        for item in items:
            if item["qty"] < 1:
                raise CheckoutError("Quantities must be at least 1.")
            product = self._products.get(item["productId"])
            if not product or str(product.shop_id) != str(shop.id) or not product.active:
                raise CheckoutError("A product in the cart is no longer available.")
            # Snapshot name, subtitle and price: later product edits must not rewrite history.
            lines.append({
                "product_id": product.id,
                "name": product.name,
                "subtitle": self._listings.subtitle(product),
                "unit_price_cents": round(float(product.price) * 100),
                "quantity": item["qty"],
            })
        subtotal_cents = sum(line["quantity"] * line["unit_price_cents"] for line in lines)
        return self._orders.create(
            str(shop.id),
            buyer_id,
            lines,
            fulfillment,
            subtotal_cents=subtotal_cents,
            shipping_cents=shipping_cents(shop, subtotal_cents) if fulfillment is Fulfillment.SHIP else 0,
            shipping_address_id=None,
            ships_within_days=shop.ships_within_days,
            pickup_code=pickup_code() if fulfillment is Fulfillment.PICKUP else None,
        )


def shipping_cents(shop: m.Shop, subtotal_cents: int) -> int:
    if shop.ship_free_over_cents is not None and subtotal_cents >= shop.ship_free_over_cents:
        return 0
    return shop.ship_flat_rate_cents


def pickup_code() -> str:
    # 4 digits reads aloud at the counter; unique enough per shop per day.
    return f"{secrets.randbelow(10_000):04d}"
