"""
DesignMirror AI — Celery Worker Configuration
================================================

MENTOR MOMENT: Why Celery?
─────────────────────────
Some tasks are too slow for a web request (e.g., running SAM AI on a room
scan takes 5-30 seconds). If we did this in the request handler, the user
would stare at a loading screen.

Celery solves this with a "task queue" pattern:
  1. The API receives the request and creates a "task" (like a ticket).
  2. The task is put into Redis (the "broker" / message queue).
  3. A separate Celery worker process picks up the task and runs it.
  4. The API immediately returns a task ID to the client.
  5. The client can poll for results or get a push notification when done.

This is the same pattern that Gmail uses for sending emails —
the "Send" button returns instantly, but the email is actually
sent by a background worker seconds later.
"""

from celery import Celery

from app.config import settings

celery_app = Celery(
    "designmirror",
    broker=settings.CELERY_BROKER_URL,
    backend=settings.CELERY_RESULT_BACKEND,
)

# Celery configuration
celery_app.conf.update(
    # Serialization
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",

    # Timezone
    timezone="UTC",
    enable_utc=True,

    # Task settings
    task_track_started=True,           # Track when a task starts running
    task_time_limit=300,               # Kill task after 5 minutes (safety net)
    task_soft_time_limit=240,          # Warn at 4 minutes

    # Worker settings
    worker_prefetch_multiplier=1,      # Don't hog tasks, take one at a time
    worker_max_tasks_per_child=100,    # Restart worker after 100 tasks (prevent memory leaks)

    # Result settings
    result_expires=3600,               # Results expire after 1 hour
)

# Auto-discover tasks in the workers module
celery_app.autodiscover_tasks(["app.workers"])

