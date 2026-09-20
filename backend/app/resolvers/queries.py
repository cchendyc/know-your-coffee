from ariadne import ObjectType, QueryType

from ..services.google import place_preview, search_places
from ..services.nlsearch import parse_search

query = QueryType()
coffee_shop = ObjectType("CoffeeShop")
chain_type = ObjectType("Chain")
user_type = ObjectType("User")


@query.field("shops")
async def resolve_shops(_, info, **filter):
    repo = info.context["repo"]
    user = info.context["user"]
    user_id = user["id"] if user else None
    shops, total = repo.list_shops(filter, user_id)

    # Lexical search first; only a query it can't satisfy costs an LLM call.
    search = (filter.get("search") or "").strip()
    if total == 0 and search:
        parsed = await parse_search(search)
        if parsed:
            retry = {
                **filter,
                "machine": filter.get("machine") or parsed["machine"],
                "city": parsed["city"] or filter.get("city"),
                "search": " ".join(parsed["terms"]),
            }
            if not retry["search"]:
                retry.pop("search")
            shops, total = repo.list_shops(retry, user_id)
    return {"shops": shops, "total": total}


@query.field("shop")
def resolve_shop(_, info, id):
    user = info.context["user"]
    return info.context["repo"].get_shop(id, user["id"] if user else None)


@query.field("cities")
def resolve_cities(_, info):
    return info.context["repo"].list_cities()


@query.field("me")
def resolve_me(_, info):
    return info.context["user"]


@query.field("searchPlaces")
async def resolve_search_places(_, info, query):
    if len(query.strip()) < 3:
        return []
    return await search_places(query.strip())


@query.field("placePreview")
async def resolve_place_preview(_, info, placeId):
    preview = await place_preview(placeId)
    if not preview:
        return None
    repo = info.context["repo"]
    user = info.context["user"]
    existing = repo.find_matching_shop(preview["name"], preview["lat"], preview["lng"])
    if existing and user:
        existing = repo.get_shop(existing["id"], user["id"])
    return {**preview, "existing": existing}


@coffee_shop.field("reports")
def resolve_reports(shop, info, limit=None):
    return info.context["repo"].list_reports(shop["id"], limit)


@coffee_shop.field("reportCount")
def resolve_report_count(shop, info):
    return info.context["repo"].count_reports(shop["id"])


@coffee_shop.field("photos")
def resolve_photos(shop, info, limit=None):
    return info.context["repo"].list_photos(shop["id"], limit)


@coffee_shop.field("photoCount")
def resolve_photo_count(shop, info):
    return info.context["repo"].count_photos(shop["id"])


@coffee_shop.field("chain")
def resolve_chain(shop, info):
    chain_id = shop.get("chainId")
    if not chain_id:
        return None
    return info.context["repo"].get_chain(chain_id)


@chain_type.field("shops")
def resolve_chain_shops(chain, info):
    user = info.context["user"]
    return info.context["repo"].list_chain_shops(chain["id"], user["id"] if user else None)


# Saved/been counts are only meaningful for the session user (me / auth payload).
@user_type.field("savedCount")
def resolve_saved_count(user, info):
    return info.context["repo"].user_stats(user["id"])["saved"]


@user_type.field("beenCount")
def resolve_been_count(user, info):
    return info.context["repo"].user_stats(user["id"])["been"]
