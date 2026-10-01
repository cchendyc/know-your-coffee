from .mutations import mutation
from .queries import query
from .seller import seller
from .types import category, coffee_shop, order, order_item, product, shipment

bindables = [query, mutation, category, product, order, order_item, shipment, coffee_shop, seller]
