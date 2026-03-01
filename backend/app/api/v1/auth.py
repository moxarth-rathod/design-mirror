"""
DesignMirror AI — Authentication Router
=========================================

This router handles all auth-related HTTP endpoints:
  POST /api/v1/auth/signup   → Create a new account
  POST /api/v1/auth/login    → Get JWT tokens
  POST /api/v1/auth/refresh  → Refresh expired access token
  GET  /api/v1/auth/me       → Get current user profile (protected)

MENTOR MOMENT: Router vs. Service
──────────────────────────────────
The router's job is ONLY to:
  1. Parse the HTTP request (headers, body, query params)
  2. Call the appropriate service function
  3. Return the HTTP response with the correct status code

All business logic lives in `services/auth_service.py`.
This keeps the router thin and easy to read.
"""

from fastapi import APIRouter, Depends, status
from fastapi.security import OAuth2PasswordRequestForm

from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.user import (
    PasswordChangeRequest,
    TokenRefreshRequest,
    TokenResponse,
    UserResponse,
    UserSignUpRequest,
    UserUpdateRequest,
)
from app.services import auth_service

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post(
    "/signup",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new user account",
    responses={
        409: {"description": "Email already registered"},
        422: {"description": "Validation error (weak password, invalid email)"},
    },
)
async def signup(data: UserSignUpRequest) -> UserResponse:
    """
    Register a new user.

    **Password Requirements:**
    - Minimum 8 characters
    - At least one uppercase letter
    - At least one digit

    Returns the created user profile (without password).
    """
    return await auth_service.signup_user(data)


@router.post(
    "/login",
    response_model=TokenResponse,
    summary="Login and receive JWT tokens",
    responses={
        401: {"description": "Invalid email or password"},
    },
)
async def login(form_data: OAuth2PasswordRequestForm = Depends()) -> TokenResponse:
    """
    Authenticate with email and password.

    Returns a JWT access token (15 min) and refresh token (7 days).

    NOTE: We use OAuth2PasswordRequestForm here (not our custom LoginRequest)
    because it integrates with FastAPI's Swagger UI "Authorize" button.
    The form sends `username` (we treat it as email) and `password`.
    """
    return await auth_service.login_user(
        email=form_data.username,  # OAuth2 form uses 'username' field
        password=form_data.password,
    )


@router.post(
    "/refresh",
    response_model=TokenResponse,
    summary="Refresh an expired access token",
    responses={
        401: {"description": "Invalid or expired refresh token"},
    },
)
async def refresh_token(data: TokenRefreshRequest) -> TokenResponse:
    """
    Exchange a valid refresh token for a new token pair.

    The Flutter app calls this when the access token expires (after 15 min).
    This avoids forcing the user to log in again.
    """
    return await auth_service.refresh_access_token(data.refresh_token)


@router.get(
    "/me",
    response_model=UserResponse,
    summary="Get current user profile",
    responses={
        401: {"description": "Not authenticated or invalid token"},
    },
)
async def get_me(current_user: User = Depends(get_current_user)) -> UserResponse:
    return UserResponse(
        id=str(current_user.id),
        email=current_user.email,
        full_name=current_user.full_name,
        is_active=current_user.is_active,
        created_at=current_user.created_at,
        updated_at=current_user.updated_at,
    )


@router.patch(
    "/me",
    response_model=UserResponse,
    summary="Update current user profile",
)
async def update_me(
    data: UserUpdateRequest,
    current_user: User = Depends(get_current_user),
) -> UserResponse:
    return await auth_service.update_user_profile(current_user, data)


@router.post(
    "/change-password",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Change password",
    responses={
        400: {"description": "Current password is incorrect"},
    },
)
async def change_password(
    data: PasswordChangeRequest,
    current_user: User = Depends(get_current_user),
) -> None:
    await auth_service.change_password(current_user, data)

