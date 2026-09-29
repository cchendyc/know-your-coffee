"""Domain errors. Resolvers translate them into GraphQL errors; their
messages are written for end users."""


class DomainError(Exception):
    pass


class DuplicateEmailError(DomainError):
    def __init__(self):
        super().__init__(
            "This email is already used by another account. "
            "Sign in with the method you used first."
        )


class CodeCooldownError(DomainError):
    def __init__(self, seconds_left: int):
        super().__init__(f"A code was just sent. You can resend in {seconds_left}s.")


class InvalidCodeError(DomainError):
    def __init__(self):
        super().__init__("That code is wrong or expired. Request a new one.")


class CheckoutError(DomainError):
    pass


class OutOfStockError(DomainError):
    def __init__(self, product_name: str):
        super().__init__(f"Not enough stock of {product_name}.")
