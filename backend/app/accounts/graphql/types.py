"""Field resolvers for User. The parent is either an app.models.User record
or, when the store no longer has the user, the raw session-token dict."""

from ariadne import ObjectType

user = ObjectType("User")


def user_id(parent) -> str:
    return parent["id"] if isinstance(parent, dict) else str(parent.id)


# Session tokens predate roles and store records may be richer than the
# token; always read role from the store.
@user.field("role")
def resolve_role(parent, info):
    record = info.context["repos"].users.get(user_id(parent))
    return record.role if record else "USER"


# Saved/been counts are only meaningful for the session user (me / auth payload).
@user.field("savedCount")
def resolve_saved_count(parent, info):
    return info.context["repos"].shops.viewer_stats(user_id(parent))["saved"]


@user.field("beenCount")
def resolve_been_count(parent, info):
    return info.context["repos"].shops.viewer_stats(user_id(parent))["been"]
