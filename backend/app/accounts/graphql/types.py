"""Field resolvers for User. The parent is either an app.models.User record
or, when the store no longer has the user, the raw session-token dict."""

from ariadne import ObjectType

user = ObjectType("User")


def user_id(parent) -> str:
    return parent["id"] if isinstance(parent, dict) else str(parent.id)


# Session tokens predate roles and store records may be richer than the
# token; always read role from the store.
@user.field("role")
async def resolve_role(parent, info):
    record = await info.context["loaders"].user.load(user_id(parent))
    return record.role if record else "USER"


# Saved/been counts are only meaningful for the session user (me / auth payload).
# Both fields read one loader key, so together they cost one stats query.
@user.field("savedCount")
async def resolve_saved_count(parent, info):
    stats = await info.context["loaders"].viewer_stats.load(user_id(parent))
    return stats["saved"]


@user.field("beenCount")
async def resolve_been_count(parent, info):
    stats = await info.context["loaders"].viewer_stats.load(user_id(parent))
    return stats["been"]
