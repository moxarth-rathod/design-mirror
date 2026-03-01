"""
DesignMirror AI — User Document Model (Beanie ODM)
====================================================

MENTOR MOMENT: ORM vs ODM
──────────────────────────
With PostgreSQL, we'd use an ORM (Object-Relational Mapper) like SQLAlchemy.
With MongoDB, we use an ODM (Object-Document Mapper) — same idea, different data shape.

Beanie documents are just Pydantic models that know how to save themselves to MongoDB.
So `User` below is simultaneously:
  • A Pydantic model (validates data, serializes to JSON)
  • A MongoDB document (can .insert(), .find(), .save())

PATTERN: Repository Pattern (implicit)
──────────────────────────────────────
Beanie builds the Repository pattern right into the Document class.
Instead of writing a separate UserRepository class, we call:
    user = await User.find_one(User.email == "john@example.com")
    await user.save()
This keeps our code concise without sacrificing clarity.
"""

from datetime import datetime, timezone
from typing import Optional

from beanie import Document, Indexed
from pydantic import EmailStr, Field


class User(Document):
    """
    Represents a user account in the DesignMirror system.

    Maps to the 'users' collection in MongoDB.
    """

    # ── Fields ─────────────────────────────────
    email: Indexed(EmailStr, unique=True)  # type: ignore[valid-type]
    """
    User's email address.
    • Indexed(unique=True) creates a MongoDB unique index automatically.
    • EmailStr validates the format (must contain @, valid domain, etc.).
    • This prevents duplicate sign-ups at the database level.
    """

    full_name: str = Field(..., min_length=1, max_length=100)
    """User's display name. Required, 1-100 characters."""

    hashed_password: str
    """
    Bcrypt hash of the user's password.
    SECURITY: The plaintext password is NEVER stored. We hash it in auth_service
    before creating the User document.
    """

    is_active: bool = Field(default=True)
    """
    Account status flag. Inactive accounts cannot log in.
    Useful for soft-deleting users without losing their data.
    """

    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    """Timestamp of account creation (UTC)."""

    updated_at: Optional[datetime] = Field(default=None)
    """Timestamp of last profile update (UTC). None if never updated."""

    # ── Beanie Settings ────────────────────────
    class Settings:
        """
        Beanie collection settings.

        name: The MongoDB collection name. Without this, Beanie would use
              the class name in lowercase ('user'), but we want 'users'
              to follow database naming conventions.
        """

        name = "users"

    # ── Helper Methods ─────────────────────────
    def to_public_dict(self) -> dict:
        """
        Return a safe representation of the user (no password hash).

        This is used in API responses — we never leak the hashed_password
        field to the client, even though it's not the plaintext password.
        """
        return {
            "id": str(self.id),
            "email": self.email,
            "full_name": self.full_name,
            "is_active": self.is_active,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }

