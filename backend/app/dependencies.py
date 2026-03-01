"""
DesignMirror AI — Dependency Injection
=======================================

MENTOR MOMENT: What is Dependency Injection (DI)?
─────────────────────────────────────────────────
Imagine every endpoint that needs the current user had to:
    1. Extract the token from the header
    2. Decode and validate the JWT
    3. Query the database for the user
    4. Handle all the error cases

That's ~15 lines of boilerplate REPEATED in every protected endpoint.

FastAPI's `Depends()` solves this. We write the logic ONCE here, then
any endpoint can say "I need the current user" with a single parameter:

    @router.get("/me")
    async def get_me(user: User = Depends(get_current_user)):
        return user

FastAPI automatically runs `get_current_user` before the endpoint,
extracts the token, validates it, fetches the user, and injects it.
If anything fails, it returns a 401 error — the endpoint code never runs.

PATTERN: This is classic Dependency Injection — the endpoint declares
WHAT it needs, and the framework provides HOW to get it.
"""

from fastapi import Depends
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError

from app.core.exceptions import UnauthorizedError
from app.core.logging import logger
from app.core.security import decode_token
from app.models.user import User


# ── OAuth2 Scheme ──────────────────────────────────────────────────────────────
# This tells FastAPI to look for a Bearer token in the Authorization header.
# The `tokenUrl` is used by the Swagger UI's "Authorize" button to know
# where to send login requests.
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


async def get_current_user(token: str = Depends(oauth2_scheme)) -> User:
    """
    Extract and validate the current user from a JWT access token.

    This is injected into protected endpoints via FastAPI's Depends() system.

    Flow:
        1. FastAPI extracts the Bearer token from the Authorization header.
        2. We decode the JWT and extract the user ID from the 'sub' claim.
        3. We query MongoDB for the user.
        4. We verify the user exists and is active.
        5. We return the User document — ready for the endpoint to use.

    If ANY step fails, we raise UnauthorizedError (HTTP 401).
    """
    # Step 1: Decode the JWT
    try:
        payload = decode_token(token)
    except JWTError:
        raise UnauthorizedError(
            message="Could not validate credentials",
            error_code="INVALID_TOKEN",
        )

    # Step 2: Extract user ID
    user_id: str | None = payload.get("sub")
    token_type: str | None = payload.get("type")

    if user_id is None:
        raise UnauthorizedError(
            message="Token payload is missing user ID",
            error_code="INVALID_TOKEN_PAYLOAD",
        )

    # Step 3: Ensure it's an access token (not a refresh token being misused)
    if token_type != "access":
        raise UnauthorizedError(
            message="Expected an access token",
            error_code="WRONG_TOKEN_TYPE",
        )

    # Step 4: Fetch user from MongoDB
    user = await User.get(user_id)
    if user is None:
        raise UnauthorizedError(
            message="User not found",
            error_code="USER_NOT_FOUND",
        )

    # Step 5: Check if account is still active
    if not user.is_active:
        raise UnauthorizedError(
            message="User account is deactivated",
            error_code="ACCOUNT_INACTIVE",
        )

    return user


async def get_current_active_user(
    current_user: User = Depends(get_current_user),
) -> User:
    """
    A stricter dependency that ensures the user is active.

    Usage in endpoints that require an active account:
        @router.post("/rooms/scan")
        async def create_scan(user: User = Depends(get_current_active_user)):
            ...
    """
    if not current_user.is_active:
        raise UnauthorizedError(
            message="User account is deactivated",
            error_code="ACCOUNT_INACTIVE",
        )
    return current_user

