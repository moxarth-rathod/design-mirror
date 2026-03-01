"""
DesignMirror AI — Application Configuration
=============================================
Uses Pydantic BaseSettings to load values from environment variables (.env file).

WHY Pydantic Settings?
─────────────────────
Instead of scattered os.getenv() calls everywhere, we define ONE config class.
Pydantic validates types automatically — if MONGODB_URL is missing, the app
crashes at startup with a clear error, NOT at 3 AM when a user hits that
code path for the first time.

This is a pattern called "Fail Fast" — catch misconfigurations immediately.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    Central configuration loaded from environment variables.

    Pydantic will:
    1. Read from a .env file (if it exists)
    2. Override with actual environment variables
    3. Validate types and raise errors on missing required fields
    """

    # ── App ────────────────────────────────────
    APP_NAME: str = "DesignMirror AI"
    APP_ENV: str = "development"  # development | staging | production
    DEBUG: bool = True

    # ── MongoDB ────────────────────────────────
    MONGODB_URL: str = "mongodb://designmirror_user:changeme_db_password@localhost:27017"
    MONGODB_DB_NAME: str = "designmirror"

    # ── Redis ──────────────────────────────────
    REDIS_URL: str = "redis://localhost:6379/0"

    # ── JWT (JSON Web Tokens) ──────────────────
    #   • SECRET_KEY signs tokens — MUST be random in production.
    #   • Access tokens are short-lived (15 min) to limit damage if stolen.
    #   • Refresh tokens let the user stay logged in without re-entering password.
    JWT_SECRET_KEY: str = "CHANGE_ME_TO_A_RANDOM_64_CHAR_STRING"
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    JWT_REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # ── AES-256 Encryption ─────────────────────
    #   Used to encrypt sensitive data (room scans) before storing in MongoDB.
    AES_ENCRYPTION_KEY: str = "CHANGE_ME_TO_A_32_BYTE_HEX_STRING"

    # ── MinIO ──────────────────────────────────
    MINIO_ENDPOINT: str = "localhost:9000"
    MINIO_ACCESS_KEY: str = "minioadmin"
    MINIO_SECRET_KEY: str = "minioadmin"
    MINIO_SECURE: bool = False
    MINIO_BUCKET_MODELS: str = "design-mirror-models"
    MINIO_BUCKET_SCANS: str = "design-mirror-scans"

    # ── Celery ─────────────────────────────────
    CELERY_BROKER_URL: str = "redis://localhost:6379/1"
    CELERY_RESULT_BACKEND: str = "redis://localhost:6379/2"

    # ── Pydantic Settings Config ───────────────
    model_config = SettingsConfigDict(
        env_file=".env",          # Load from .env in project root
        env_file_encoding="utf-8",
        case_sensitive=True,      # ENV vars are case-sensitive
        extra="ignore",           # Ignore unknown env vars
    )


# ── Singleton Instance ─────────────────────────
# Create one settings object that the entire app shares.
# This is the Singleton pattern — one source of truth for config.
settings = Settings()

