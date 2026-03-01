"""
DesignMirror AI — User Schemas (Pydantic)
==========================================

MENTOR MOMENT: Why separate Schemas from Models?
─────────────────────────────────────────────────
• Models (app/models/user.py) = how data is STORED in MongoDB.
• Schemas (this file) = how data is RECEIVED from and SENT TO the client.

This separation is critical for security:
  - The User model has `hashed_password` — we NEVER send that to the client.
  - The signup schema has `password` — we NEVER store that directly.
  - By having separate classes, it's impossible to accidentally leak sensitive fields.

Think of it like a restaurant:
  - Schema (Request) = the order form the customer fills out.
  - Model = the recipe card the kitchen uses.
  - Schema (Response) = the plated dish the customer sees.
  The customer never sees the recipe, and the kitchen never stores the order form.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field, field_validator


# ── Request Schemas (what the client sends) ───────────────────────────────────

class UserSignUpRequest(BaseModel):
    """Schema for user registration."""

    email: EmailStr
    """Must be a valid email address."""

    full_name: str = Field(..., min_length=1, max_length=100)
    """Display name: 1-100 characters."""

    password: str = Field(..., min_length=8, max_length=128)
    """
    Plaintext password from the user.
    Rules:
      • 8-128 characters
      • Must contain at least one uppercase letter
      • Must contain at least one digit
    """

    @field_validator("password")
    @classmethod
    def validate_password_strength(cls, v: str) -> str:
        """
        Enforce password complexity rules.

        WHY? Weak passwords are the #1 cause of account breaches.
        These rules catch the most common weak passwords without being
        annoyingly strict (no "must include wingdings" rules).
        """
        if not any(c.isupper() for c in v):
            raise ValueError("Password must contain at least one uppercase letter")
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one digit")
        return v


class UserLoginRequest(BaseModel):
    """Schema for user login."""

    email: EmailStr
    password: str


# ── Response Schemas (what the client receives) ───────────────────────────────

class UserResponse(BaseModel):
    """
    Public user profile — returned by /me and signup endpoints.
    Notice: NO password field. The client never sees the hash.
    """

    id: str
    email: EmailStr
    full_name: str
    is_active: bool
    created_at: datetime
    updated_at: Optional[datetime] = None


class UserUpdateRequest(BaseModel):
    """Schema for updating user profile fields."""

    full_name: Optional[str] = Field(default=None, min_length=1, max_length=100)


class PasswordChangeRequest(BaseModel):
    """Schema for changing the user's password."""

    current_password: str
    new_password: str = Field(..., min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def validate_password_strength(cls, v: str) -> str:
        if not any(c.isupper() for c in v):
            raise ValueError("Password must contain at least one uppercase letter")
        if not any(c.isdigit() for c in v):
            raise ValueError("Password must contain at least one digit")
        return v


class TokenResponse(BaseModel):
    """
    JWT token pair returned after login or token refresh.

    The Flutter app stores these tokens and sends the access_token
    in the Authorization header: `Bearer <access_token>`
    """

    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class TokenRefreshRequest(BaseModel):
    """Schema for refreshing an expired access token."""

    refresh_token: str

