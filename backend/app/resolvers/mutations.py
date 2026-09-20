from ariadne import MutationType
from graphql import GraphQLError

from ..auth import create_session_token, verify_google_id_token
from ..services.google import fetch_shops_from_google, new_shop_from_place
from ..services.vision import identify_machine, parse_menu
from ..services.yelp import fetch_shops_from_yelp

mutation = MutationType()


def _require_user(info) -> dict:
    user = info.context["user"]
    if not user:
        raise GraphQLError("Sign in with Google to contribute.")
    return user


@mutation.field("signInWithGoogle")
async def resolve_sign_in(_, info, idToken):
    identity = await verify_google_id_token(idToken)
    user = info.context["repo"].upsert_user(
        {
            "googleSub": identity["sub"],
            "email": identity["email"],
            "name": identity["name"],
            "picture": identity["picture"],
        }
    )
    session = {"id": user["id"], "name": user["name"], "email": user["email"], "picture": user["picture"]}
    return {"token": create_session_token(session), "user": session}


@mutation.field("addShopFromPlace")
async def resolve_add_shop_from_place(_, info, placeId):
    _require_user(info)
    shop = await new_shop_from_place(placeId)
    if not shop:
        raise GraphQLError("That place could not be loaded from Google Places. Try searching again.")
    return info.context["repo"].upsert_shops([shop])[0]


@mutation.field("submitReport")
def resolve_submit_report(_, info, input):
    user = _require_user(info)
    repo = info.context["repo"]
    if not repo.get_shop(input["shopId"]):
        raise GraphQLError(f"Shop {input['shopId']} not found")
    return repo.add_report({**input, "userId": user["id"]})


@mutation.field("setShopStatus")
def resolve_set_shop_status(_, info, shopId, saved=None, been=None):
    user = _require_user(info)
    repo = info.context["repo"]
    repo.set_shop_status(user["id"], shopId, saved, been)
    shop = repo.get_shop(shopId, user["id"])
    if not shop:
        raise GraphQLError(f"Shop {shopId} not found")
    return shop


@mutation.field("addShopPhotos")
def resolve_add_shop_photos(_, info, shopId, photos):
    user = _require_user(info)
    repo = info.context["repo"]
    if not repo.get_shop(shopId):
        raise GraphQLError(f"Shop {shopId} not found")
    if len(photos) > 8:
        raise GraphQLError("At most 8 photos per submission.")
    for p in photos:
        # ~700KB data-URL cap keeps rows small; clients downscale before upload.
        if len(p["data"]) > 700_000:
            raise GraphQLError("A photo is too large. Please retry; it will be resized.")
    return repo.add_photos(shopId, user["id"], photos)


@mutation.field("identifyMachine")
async def resolve_identify_machine(_, info, imageBase64):
    return await identify_machine(imageBase64)


@mutation.field("parseMenu")
async def resolve_parse_menu(_, info, imageBase64):
    return await parse_menu(imageBase64)


@mutation.field("importShopsFromYelp")
async def resolve_import_yelp(_, info, location):
    shops = await fetch_shops_from_yelp(location)
    return info.context["repo"].upsert_shops(shops)


@mutation.field("importShopsFromGoogle")
async def resolve_import_google(_, info, location):
    shops = await fetch_shops_from_google(location)
    return info.context["repo"].upsert_shops(shops)
