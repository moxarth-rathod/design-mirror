"""
DesignMirror AI — Health Check Router
=======================================

MENTOR MOMENT: Why a health check?
──────────────────────────────────
In production, Docker, Kubernetes, and load balancers need to know if
your app is alive and healthy. They periodically hit /health and:
  • If it returns 200 → the app is running, keep sending traffic.
  • If it fails → restart the container or stop routing traffic to it.

We check THREE things:
  1. The app process is running (if this endpoint responds at all)
  2. MongoDB is reachable (can we ping it?)
  3. Redis is reachable (can we ping it?)

If any dependency is down, we return a degraded status so the ops team
can investigate before users start seeing errors.
"""

from fastapi import APIRouter
from motor.motor_asyncio import AsyncIOMotorClient
from redis.asyncio import Redis

from app.config import settings
from app.core.logging import logger

router = APIRouter(tags=["Health"])


@router.get(
    "/health",
    summary="Application health check",
    response_description="Health status of the application and its dependencies",
)
async def health_check() -> dict:
    """
    Check the health of the application and its dependencies.

    Returns:
        A dict with overall status and individual service statuses.
    """
    health = {
        "status": "healthy",
        "service": settings.APP_NAME,
        "environment": settings.APP_ENV,
        "dependencies": {},
    }

    # ── Check MongoDB ──────────────────────────
    try:
        client = AsyncIOMotorClient(
            settings.MONGODB_URL,
            serverSelectionTimeoutMS=2000,  # 2 second timeout
        )
        await client.admin.command("ping")
        health["dependencies"]["mongodb"] = "healthy"
        client.close()
    except Exception as e:
        logger.warning("MongoDB health check failed: {}", str(e))
        health["dependencies"]["mongodb"] = "unhealthy"
        health["status"] = "degraded"

    # ── Check Redis ────────────────────────────
    try:
        redis = Redis.from_url(
            settings.REDIS_URL,
            socket_connect_timeout=2,  # 2 second timeout
        )
        await redis.ping()
        health["dependencies"]["redis"] = "healthy"
        await redis.aclose()
    except Exception as e:
        logger.warning("Redis health check failed: {}", str(e))
        health["dependencies"]["redis"] = "unhealthy"
        health["status"] = "degraded"

    return health

