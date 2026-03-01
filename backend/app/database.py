"""
DesignMirror AI — Database Connection (MongoDB + Beanie)
=========================================================

MENTOR MOMENT: MongoDB vs. PostgreSQL
──────────────────────────────────────
PostgreSQL is a "relational" database — data lives in rigid tables with rows.
MongoDB is a "document" database — data lives as flexible JSON-like documents.

For DesignMirror, MongoDB is great because:
  • Room scans are complex nested objects (3D coordinates, point clouds)
  • Furniture catalogs have varying attributes (sofa ≠ lamp ≠ table)
  • Documents map naturally to Python dicts / Pydantic models

We use two libraries:
  • Motor  — async MongoDB driver (like an async version of PyMongo)
  • Beanie — async ODM (Object Document Mapper) built on Motor + Pydantic v2
    Think of Beanie as "SQLAlchemy for MongoDB" — it lets us define document
    models as Python classes and query them with clean, typed methods.
"""

from motor.motor_asyncio import AsyncIOMotorClient
from beanie import init_beanie

from app.config import settings
from app.core.logging import logger

# This will hold a reference to the Motor client so we can close it on shutdown.
_motor_client: AsyncIOMotorClient | None = None


async def connect_to_mongodb() -> None:
    """
    Initialize the MongoDB connection and register Beanie document models.

    Called once at application startup (in main.py lifespan).

    HOW IT WORKS:
    1. Motor opens an async connection pool to MongoDB.
    2. Beanie scans our document model classes and creates internal mappings.
    3. After this, any Document.find() or Document.insert() call uses
       the connection pool — no manual connection management needed.
    """
    global _motor_client

    logger.info("Connecting to MongoDB at {}", settings.MONGODB_URL[:30] + "...")

    _motor_client = AsyncIOMotorClient(settings.MONGODB_URL)

    # Import document models here to avoid circular imports.
    # Every Beanie Document class we want to use MUST be listed here.
    from app.models.user import User
    from app.models.room import Room
    from app.models.product import Product
    from app.models.wishlist import WishlistItem
    from app.models.fitcheck_history import FitCheckHistory

    await init_beanie(
        database=_motor_client[settings.MONGODB_DB_NAME],
        document_models=[
            User,
            Room,
            Product,
            WishlistItem,
            FitCheckHistory,
        ],
    )

    logger.info("✅ MongoDB connected — database: {}", settings.MONGODB_DB_NAME)


async def close_mongodb_connection() -> None:
    """
    Gracefully close the MongoDB connection pool.

    Called at application shutdown. Without this, the app could leave
    orphaned connections that eat up MongoDB's connection limit.
    """
    global _motor_client

    if _motor_client is not None:
        _motor_client.close()
        logger.info("MongoDB connection closed.")

