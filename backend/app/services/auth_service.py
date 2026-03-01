"""
DesignMirror AI — Authentication Service
==========================================

This is the BUSINESS LOGIC layer for authentication. It sits between
the API router (which handles HTTP) and the database models.

PATTERN: Service Layer
──────────────────────
Why not put this logic directly in the router?
  1. Testability — we can test auth_service without spinning up a web server.
  2. Reusability — if we add a CLI tool later, it can reuse the same logic.
  3. Separation of Concerns — the router only handles HTTP; the service
     handles business rules.

Think of it like a Python function vs. a script:
  • Router = the script that handles command-line args
  • Service = the function that does the actual work
"""

from datetime import datetime, timezone

from jose import JWTError

from app.core.exceptions import (
    BadRequestError,
    ConflictError,
    UnauthorizedError,
)
from app.core.logging import logger
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)
from app.models.user import User
from app.schemas.user import (
    PasswordChangeRequest,
    TokenResponse,
    UserResponse,
    UserSignUpRequest,
    UserUpdateRequest,
)


async def signup_user(data: UserSignUpRequest) -> UserResponse:
    """
    Register a new user account.

    Steps:
      1. Check if email already exists (prevent duplicates).
      2. Hash the password (NEVER store plaintext).
      3. Create the User document in MongoDB.
      4. Return the public user profile (no password hash).

    RACE CONDITION NOTE:
    ────────────────────
    What if two requests try to sign up with the same email simultaneously?
    The unique index on `email` in MongoDB will reject the second insert,
    even if our Python check (step 1) passed for both. That's why we have
    BOTH the application-level check AND the database-level unique index.
    Defense in depth!
    """
    # Step 1: Check for existing user
    existing = await User.find_one(User.email == data.email)
    if existing:
        raise ConflictError(
            message="A user with this email already exists",
            error_code="EMAIL_ALREADY_EXISTS",
        )

    # Step 2: Hash the password
    hashed = hash_password(data.password)

    # Step 3: Create and insert the user document
    user = User(
        email=data.email,
        full_name=data.full_name,
        hashed_password=hashed,
    )
    await user.insert()

    logger.info("New user registered: {}", data.email)

    # Step 4: Return safe public response
    return UserResponse(
        id=str(user.id),
        email=user.email,
        full_name=user.full_name,
        is_active=user.is_active,
        created_at=user.created_at,
        updated_at=user.updated_at,
    )


async def login_user(email: str, password: str) -> TokenResponse:
    """
    Authenticate a user and return JWT tokens.

    SECURITY NOTES:
    ───────────────
    • We use the SAME error message for "user not found" and "wrong password".
      WHY? If we said "user not found", an attacker could enumerate which
      emails are registered in our system. This is called "user enumeration"
      and it's a real attack vector.

    • We check `is_active` AFTER password verification to avoid timing attacks
      that could reveal whether a deactivated account exists.
    """
    # Find user by email
    user = await User.find_one(User.email == email)

    # Verify credentials (same error for both cases — see security note above)
    if not user or not verify_password(password, user.hashed_password):
        raise UnauthorizedError(
            message="Invalid email or password",
            error_code="INVALID_CREDENTIALS",
        )

    # Check if account is active
    if not user.is_active:
        raise UnauthorizedError(
            message="This account has been deactivated",
            error_code="ACCOUNT_INACTIVE",
        )

    # Generate token pair
    access_token = create_access_token(subject=str(user.id))
    refresh_token = create_refresh_token(subject=str(user.id))

    logger.info("User logged in: {}", email)

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
    )


async def refresh_access_token(refresh_token: str) -> TokenResponse:
    """
    Issue a new access token using a valid refresh token.

    This allows the Flutter app to keep the user logged in without
    storing their password. When the 15-minute access token expires,
    the app sends the refresh token to get a new one.
    """
    try:
        payload = decode_token(refresh_token)
    except JWTError:
        raise UnauthorizedError(
            message="Invalid or expired refresh token",
            error_code="INVALID_REFRESH_TOKEN",
        )

    # Verify it's actually a refresh token (not a reused access token)
    if payload.get("type") != "refresh":
        raise BadRequestError(
            message="Token is not a refresh token",
            error_code="WRONG_TOKEN_TYPE",
        )

    user_id = payload.get("sub")
    if not user_id:
        raise UnauthorizedError(
            message="Invalid token payload",
            error_code="INVALID_TOKEN_PAYLOAD",
        )

    # Verify user still exists and is active
    user = await User.get(user_id)
    if not user or not user.is_active:
        raise UnauthorizedError(
            message="User not found or inactive",
            error_code="USER_NOT_FOUND",
        )

    # Issue new token pair
    new_access = create_access_token(subject=str(user.id))
    new_refresh = create_refresh_token(subject=str(user.id))

    return TokenResponse(
        access_token=new_access,
        refresh_token=new_refresh,
    )


async def update_user_profile(user: User, data: UserUpdateRequest) -> UserResponse:
    """Update mutable profile fields (currently just full_name)."""
    if data.full_name is not None:
        user.full_name = data.full_name
    user.updated_at = datetime.now(timezone.utc)
    await user.save()
    logger.info("Profile updated for user {}", str(user.id))
    return UserResponse(
        id=str(user.id),
        email=user.email,
        full_name=user.full_name,
        is_active=user.is_active,
        created_at=user.created_at,
        updated_at=user.updated_at,
    )


async def change_password(user: User, data: PasswordChangeRequest) -> None:
    """Verify current password and set a new one."""
    if not verify_password(data.current_password, user.hashed_password):
        raise BadRequestError(
            message="Current password is incorrect",
            error_code="WRONG_PASSWORD",
        )
    user.hashed_password = hash_password(data.new_password)
    user.updated_at = datetime.now(timezone.utc)
    await user.save()
    logger.info("Password changed for user {}", str(user.id))


async def get_current_user_profile(user_id: str) -> UserResponse:
    """
    Fetch the current user's profile by ID.

    Called by the /me endpoint after JWT verification.
    """
    user = await User.get(user_id)
    if not user:
        raise UnauthorizedError(
            message="User not found",
            error_code="USER_NOT_FOUND",
        )

    return UserResponse(
        id=str(user.id),
        email=user.email,
        full_name=user.full_name,
        is_active=user.is_active,
        created_at=user.created_at,
        updated_at=user.updated_at,
    )

