"""Field resolvers for shop-domain GraphQL types.

snake_case_fallback_resolvers covers plain column fields; only computed
fields and stored-jsonb camelCase keys get explicit resolvers here."""

from ariadne import ObjectType

from ..text import norm_coffees

coffee_shop = ObjectType("CoffeeShop")
coffee = ObjectType("Coffee")
chain = ObjectType("Chain")
report = ObjectType("Report")
shop_photo = ObjectType("ShopPhoto")


def viewer_id(info) -> str | None:
    user = info.context["user"]
    return user["id"] if user else None


@coffee_shop.field("ownerId")
def resolve_owner_id(shop, _info):
    return shop.owner_user_id


@coffee_shop.field("owner")
def resolve_owner(shop, info):
    if not shop.owner_user_id:
        return None
    return info.context["repos"].users.get(str(shop.owner_user_id))


@coffee_shop.field("ownedByMe")
def resolve_owned_by_me(shop, info):
    user = info.context["user"]
    return bool(user and str(shop.owner_user_id or "") == user["id"])


@coffee_shop.field("sellerOnboarded")
def resolve_seller_onboarded(shop, _info):
    return shop.seller_onboarded_at is not None


@coffee_shop.field("updatedAt")
def resolve_updated_at(shop, _info):
    return shop.updated_at.isoformat()


@coffee_shop.field("coffees")
def resolve_shop_coffees(shop, _info):
    # Stored jsonb is sparse; the schema promises non-null lists.
    return norm_coffees(shop.coffees)


@coffee_shop.field("chain")
def resolve_shop_chain(shop, info):
    return info.context["repos"].chains.get(str(shop.chain_id)) if shop.chain_id else None


@coffee_shop.field("reports")
def resolve_shop_reports(shop, info, limit=None):
    return info.context["repos"].reports.list(str(shop.id), limit)


@coffee_shop.field("reportCount")
def resolve_shop_report_count(shop, info):
    return info.context["repos"].reports.count(str(shop.id))


@coffee_shop.field("photos")
def resolve_shop_photos(shop, info, limit=None):
    return info.context["repos"].photos.list(str(shop.id), limit)


@coffee_shop.field("photoCount")
def resolve_shop_photo_count(shop, info):
    return info.context["repos"].photos.count(str(shop.id))


# Coffee parents are jsonb documents with stored camelCase keys.
@coffee.field("roastLevel")
def resolve_roast_level(doc, _info):
    return doc.get("roastLevel")


@coffee.field("tastingNotes")
def resolve_tasting_notes(doc, _info):
    return doc.get("tastingNotes") or []


@chain.field("shops")
def resolve_chain_shops(chain_row, info):
    return info.context["repos"].chains.list_shops(str(chain_row.id), viewer_id(info))


@report.field("reporter")
def resolve_reporter(report_row, _info):
    return report_row.user


@report.field("coffees")
def resolve_report_coffees(report_row, _info):
    return norm_coffees(report_row.coffees) if report_row.coffees is not None else None


@report.field("createdAt")
def resolve_report_created_at(report_row, _info):
    return report_row.created_at.isoformat()


@shop_photo.field("uploader")
def resolve_uploader(photo, _info):
    return photo.user


@shop_photo.field("createdAt")
def resolve_photo_created_at(photo, _info):
    return photo.created_at.isoformat()
