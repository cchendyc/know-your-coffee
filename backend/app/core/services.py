"""Service wiring: business logic between resolvers and repositories."""

from dataclasses import dataclass

from .repositories import Repositories


@dataclass(frozen=True)
class Services:
    auth: "AuthService"
    checkout: "CheckoutService"
    shop_imports: "ShopImportService"


def create_services(repos: Repositories) -> Services:
    from ..accounts.services.auth_service import AuthService
    from ..commerce.services.checkout_service import CheckoutService
    from ..shops.services.import_service import ShopImportService

    return Services(
        auth=AuthService(repos.users),
        checkout=CheckoutService(repos.products, repos.orders),
        shop_imports=ShopImportService(repos.shops, repos.chains),
    )
