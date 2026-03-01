"""
DesignMirror AI — Logging Configuration (Loguru)
==================================================

WHY Loguru over Python's built-in logging?
──────────────────────────────────────────
Python's default logging module requires ~10 lines of boilerplate just to get
colored terminal output. Loguru gives us:
  • Colors and formatting out of the box
  • Automatic rotation of log files (prevent 10GB log files)
  • Structured JSON logging for production (parsed by tools like Datadog)
  • Exception tracing with variable values (not just line numbers)

SECURITY RULE:
  NEVER log passwords, tokens, or encryption keys.
  Use logger.info("User {} logged in", user.email) — NOT logger.info(f"Token: {token}")
"""

import sys

from loguru import logger


def setup_logging(app_env: str = "development") -> None:
    """
    Configure Loguru for the current environment.

    Development → colorful, human-readable output to terminal.
    Production  → structured JSON to file with rotation.
    """
    # Remove default Loguru handler (avoid duplicate output)
    logger.remove()

    if app_env == "production":
        # Production: JSON-formatted logs → file, rotated daily, kept 30 days
        logger.add(
            "logs/designmirror_{time:YYYY-MM-DD}.log",
            rotation="00:00",       # New file at midnight
            retention="30 days",    # Auto-delete old logs
            compression="gz",       # Compress rotated files
            serialize=True,         # Output as JSON (machine-parseable)
            level="INFO",
            enqueue=True,           # Thread-safe async writing
        )
    else:
        # Development: Pretty, colorful output to terminal
        logger.add(
            sys.stderr,
            colorize=True,
            format=(
                "<green>{time:HH:mm:ss}</green> | "
                "<level>{level: <8}</level> | "
                "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> | "
                "<level>{message}</level>"
            ),
            level="DEBUG",
        )

    logger.info("Logging configured for '{}' environment.", app_env)


# Re-export logger so other modules can do: from app.core.logging import logger
__all__ = ["logger", "setup_logging"]

