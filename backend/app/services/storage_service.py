"""
DesignMirror AI — Storage Service (MinIO / S3)
================================================
Handles file uploads and deletions for room photos using MinIO.
"""

import uuid
from io import BytesIO

from minio import Minio

from app.config import settings
from app.core.logging import logger

BUCKET = "design-mirror-photos"


def _get_client() -> Minio:
    return Minio(
        endpoint=settings.MINIO_ENDPOINT,
        access_key=settings.MINIO_ACCESS_KEY,
        secret_key=settings.MINIO_SECRET_KEY,
        secure=settings.MINIO_SECURE,
    )


def ensure_bucket() -> None:
    client = _get_client()
    if not client.bucket_exists(BUCKET):
        client.make_bucket(BUCKET)
        logger.info("Created MinIO bucket: {}", BUCKET)


def upload_photo(data: bytes, content_type: str, user_id: str) -> str:
    """Upload a photo and return the object URL."""
    client = _get_client()
    ensure_bucket()

    ext = "jpg"
    if "png" in content_type:
        ext = "png"
    elif "webp" in content_type:
        ext = "webp"

    object_name = f"rooms/{user_id}/{uuid.uuid4().hex}.{ext}"
    client.put_object(
        BUCKET,
        object_name,
        BytesIO(data),
        length=len(data),
        content_type=content_type,
    )

    url = f"http://{settings.MINIO_ENDPOINT}/{BUCKET}/{object_name}"
    logger.info("Photo uploaded: {}", object_name)
    return url


def delete_photo(url: str) -> None:
    """Delete a photo by its URL."""
    client = _get_client()
    prefix = f"http://{settings.MINIO_ENDPOINT}/{BUCKET}/"
    if url.startswith(prefix):
        object_name = url[len(prefix):]
        client.remove_object(BUCKET, object_name)
        logger.info("Photo deleted: {}", object_name)
