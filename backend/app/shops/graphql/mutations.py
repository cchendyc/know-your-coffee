"""Shop contribution and admin mutations."""

from ariadne import MutationType
from graphql import GraphQLError

from ...core.graphql import require_admin, require_shop_owner, require_user
from ...services.vision import identify_machine, parse_menu

mutation = MutationType()


@mutation.field("addShopFromPlace")
async def resolve_add_shop_from_place(_, info, placeId):
    require_user(info)
    shop = await info.context["services"].shop_imports.from_place(placeId)
    if not shop:
        raise GraphQLError("That place could not be loaded from Google Places. Try searching again.")
    return shop


def report_fields(input: dict) -> dict:
    """ReportInput keys -> reports column values."""
    return {
        "machine": input.get("machine"),
        "machine_model": input.get("machineModel"),
        "machines": input.get("machines"),
        "bean_source": input.get("beanSource"),
        "roaster": input.get("roaster"),
        "bean_origins": input.get("beanOrigins"),
        "coffees": input.get("coffees"),
        "grinders": input.get("grinders"),
        "drinks": input.get("drinks"),
        "milk_brands": input.get("milkBrands"),
        "dog_friendly": input.get("dogFriendly"),
        "wifi": input.get("wifi"),
        "outdoor_seating": input.get("outdoorSeating"),
    }


@mutation.field("submitReport")
def resolve_submit_report(_, info, input):
    user = require_user(info)
    repos = info.context["repos"]
    if not repos.shops.get(input["shopId"]):
        raise GraphQLError(f"Shop {input['shopId']} not found")
    return repos.reports.add(
        shop_id=input["shopId"],
        user_id=user["id"],
        note=input.get("note"),
        source=input.get("source") or "TEXT",
        fields=report_fields(input),
    )


MAX_REVIEW_BODY = 2000


@mutation.field("submitReview")
def resolve_submit_review(_, info, input):
    user = require_user(info)
    repos = info.context["repos"]
    if not repos.shops.get(input["shopId"]):
        raise GraphQLError(f"Shop {input['shopId']} not found")
    rating = input["rating"]
    if not isinstance(rating, int) or rating < 1 or rating > 5:
        raise GraphQLError("Rating must be a whole number from 1 to 5.")
    body = (input.get("body") or "").strip() or None
    if body and len(body) > MAX_REVIEW_BODY:
        raise GraphQLError(f"Reviews can be at most {MAX_REVIEW_BODY} characters.")
    return repos.reviews.upsert(input["shopId"], user["id"], rating, body)


@mutation.field("setShopStatus")
def resolve_set_shop_status(_, info, shopId, saved=None, been=None):
    user = require_user(info)
    repos = info.context["repos"]
    repos.shops.set_status(user["id"], shopId, saved, been)
    shop = repos.shops.get(shopId, user["id"])
    if not shop:
        raise GraphQLError(f"Shop {shopId} not found")
    return shop


@mutation.field("addShopPhotos")
def resolve_add_shop_photos(_, info, shopId, photos):
    user = require_user(info)
    repos = info.context["repos"]
    if not repos.shops.get(shopId):
        raise GraphQLError(f"Shop {shopId} not found")
    if len(photos) > 8:
        raise GraphQLError("At most 8 photos per submission.")
    for photo in photos:
        # ~700KB data-URL cap keeps rows small; clients downscale before upload.
        if len(photo["data"]) > 700_000:
            raise GraphQLError("A photo is too large. Please retry; it will be resized.")
    return repos.photos.add(shopId, user["id"], photos)


@mutation.field("updateShopProfile")
def resolve_update_shop_profile(_, info, shopId, input):
    user = require_shop_owner(info, shopId)
    changes = {}
    if "vibe" in input:
        changes["vibe"] = (input["vibe"] or "").strip() or None
    if "website" in input:
        changes["website"] = (input["website"] or "").strip() or None
    repos = info.context["repos"]
    repos.shops.update_profile(shopId, changes)
    return repos.shops.get(shopId, user["id"])


@mutation.field("completeSellerOnboarding")
def resolve_complete_seller_onboarding(_, info, shopId):
    user = require_shop_owner(info, shopId)
    repos = info.context["repos"]
    repos.shops.complete_seller_onboarding(shopId)
    return repos.shops.get(shopId, user["id"])


@mutation.field("identifyMachine")
async def resolve_identify_machine(_, info, imageBase64):
    require_user(info)
    return await identify_machine(imageBase64)


@mutation.field("parseMenu")
async def resolve_parse_menu(_, info, imageBase64):
    require_user(info)
    return await parse_menu(imageBase64)


@mutation.field("importShopsFromYelp")
async def resolve_import_yelp(_, info, location):
    require_admin(info)
    return await info.context["services"].shop_imports.from_yelp(location)


@mutation.field("importShopsFromGoogle")
async def resolve_import_google(_, info, location):
    require_admin(info)
    return await info.context["services"].shop_imports.from_google(location)


@mutation.field("deleteShop")
def resolve_delete_shop(_, info, id):
    require_admin(info)
    if not info.context["repos"].shops.delete(id):
        raise GraphQLError(f"Shop {id} not found")
    return True
