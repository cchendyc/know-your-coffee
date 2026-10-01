"""Seller-hub and buyer queries."""

from ariadne import QueryType

from ...core.graphql import page_bounds, require_shop_owner
from ...models.enums import ListingStatus
from .seller import owned_shop_ids

query = QueryType()


@query.field("categories")
def resolve_categories(_, info):
    return info.context["repos"].categories.list()


@query.field("product")
def resolve_product(_, info, id):
    repos = info.context["repos"]
    product = repos.products.get(id)
    if not product:
        return None
    if product.active:
        return product
    user = info.context["user"]
    shop = repos.shops.get(str(product.shop_id))
    is_owner = bool(user and shop and str(shop.owner_user_id or "") == user["id"])
    return product if is_owner else None


@query.field("myProducts")
def resolve_my_products(_, info, shopId, limit, offset, status=None):
    require_shop_owner(info, shopId)
    rows, total = info.context["repos"].products.page(shopId, status, *page_bounds(limit, offset))
    return {"products": rows, "total": total}


@query.field("myProductCounts")
def resolve_my_product_counts(_, info, shopId):
    require_shop_owner(info, shopId)
    counts = info.context["repos"].products.status_counts(shopId)
    return {
        "total": sum(counts.values()),
        "in_stock": counts[ListingStatus.IN_STOCK],
        "low_stock": counts[ListingStatus.LOW_STOCK],
        "hidden": counts[ListingStatus.HIDDEN],
    }


@query.field("myOrders")
def resolve_my_orders(_, info, limit, offset, shopId=None, status=None):
    shop_ids = owned_shop_ids(info, shopId)
    rows, total = info.context["repos"].orders.page_for_shops(shop_ids, status, *page_bounds(limit, offset))
    return {"orders": rows, "total": total}


@query.field("myShipments")
def resolve_my_shipments(_, info, limit, offset, shopId=None, status=None):
    shop_ids = owned_shop_ids(info, shopId)
    rows, total = info.context["repos"].shipments.page_for_shops(shop_ids, status, *page_bounds(limit, offset))
    return {"shipments": rows, "total": total}


@query.field("mySeller")
def resolve_my_seller(_, info):
    user = info.context["user"]
    shops = info.context["repos"].shops.list_owned(user["id"]) if user else []
    return {"shops": shops} if shops else None


@query.field("myPurchases")
def resolve_my_purchases(_, info):
    user = info.context["user"]
    return info.context["repos"].orders.list_purchases(user["id"]) if user else []
