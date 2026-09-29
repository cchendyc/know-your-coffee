"""Shop discovery queries."""

from ariadne import QueryType

from ...core.graphql import require_user
from ...services.google import place_preview, search_places
from ...services.nlsearch import parse_search
from .types import viewer_id

query = QueryType()


@query.field("shops")
async def resolve_shops(_, info, **filter):
    repos = info.context["repos"]
    shops, total = repos.shops.list(filter, viewer_id(info))

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
            shops, total = repos.shops.list(retry, viewer_id(info))
    return {"shops": shops, "total": total}


@query.field("shop")
def resolve_shop(_, info, id):
    return info.context["repos"].shops.get(id, viewer_id(info))


@query.field("cities")
def resolve_cities(_, info):
    return info.context["repos"].shops.cities()


@query.field("myShops")
def resolve_my_shops(_, info):
    user = info.context["user"]
    return info.context["repos"].shops.list_owned(user["id"]) if user else []


@query.field("searchPlaces")
async def resolve_search_places(_, info, query):
    # Each call spends Google Places quota, so it is not open to anonymous traffic.
    require_user(info)
    if len(query.strip()) < 3:
        return []
    return await search_places(query.strip())


@query.field("placePreview")
async def resolve_place_preview(_, info, placeId):
    require_user(info)
    preview = await place_preview(placeId)
    if not preview:
        return None
    repos = info.context["repos"]
    match = repos.shops.find_matching(preview["name"], preview["lat"], preview["lng"])
    existing = repos.shops.get(str(match.id), viewer_id(info)) if match else None
    return {**preview, "existing": existing}
