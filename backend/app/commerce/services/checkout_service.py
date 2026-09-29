"""Checkout: cart validation, price snapshots, order creation."""

from ... import models as m
from ...core.errors import CheckoutError
from ...models.enums import Fulfillment


class CheckoutService:
    def __init__(self, products, orders):
        self._products = products
        self._orders = orders

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
            # Snapshot name and price: later product edits must not rewrite history.
            lines.append({
                "productId": str(product.id),
                "name": product.name,
                "qty": item["qty"],
                "unitPrice": float(product.price),
            })
        total = round(sum(line["qty"] * line["unitPrice"] for line in lines), 2)
        return self._orders.create(str(shop.id), buyer_id, lines, total, fulfillment)
