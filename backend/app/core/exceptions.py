"""
DesignMirror AI — Custom Exception Handlers
=============================================

WHY custom exceptions?
─────────────────────
FastAPI's default error responses are plain and inconsistent.
By defining our own exceptions, we ensure:
  • Every error response has the SAME JSON shape: {"detail": "...", "error_code": "..."}
  • We can log errors centrally (instead of try/except everywhere)
  • The Flutter app only needs to parse ONE error format

PATTERN: This uses the "Exception Handler" pattern — we register handlers
in main.py that catch these exceptions and return clean HTTP responses.
"""

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
from app.core.logging import logger


# ── Custom Exception Classes ──────────────────────────────────────────────────

class DesignMirrorException(Exception):
    """Base exception for all DesignMirror errors."""

    def __init__(self, message: str, error_code: str, status_code: int = 500):
        self.message = message
        self.error_code = error_code
        self.status_code = status_code
        super().__init__(message)


class BadRequestError(DesignMirrorException):
    """Client sent invalid data (HTTP 400)."""

    def __init__(self, message: str = "Bad request", error_code: str = "BAD_REQUEST"):
        super().__init__(message=message, error_code=error_code, status_code=400)


class UnauthorizedError(DesignMirrorException):
    """Authentication required or failed (HTTP 401)."""

    def __init__(
        self, message: str = "Not authenticated", error_code: str = "UNAUTHORIZED"
    ):
        super().__init__(message=message, error_code=error_code, status_code=401)


class ForbiddenError(DesignMirrorException):
    """Authenticated but not allowed to access this resource (HTTP 403)."""

    def __init__(
        self,
        message: str = "Access forbidden",
        error_code: str = "FORBIDDEN",
    ):
        super().__init__(message=message, error_code=error_code, status_code=403)


class NotFoundError(DesignMirrorException):
    """Resource not found (HTTP 404)."""

    def __init__(
        self, message: str = "Resource not found", error_code: str = "NOT_FOUND"
    ):
        super().__init__(message=message, error_code=error_code, status_code=404)


class ConflictError(DesignMirrorException):
    """Resource already exists (HTTP 409). E.g., duplicate email on signup."""

    def __init__(
        self, message: str = "Resource already exists", error_code: str = "CONFLICT"
    ):
        super().__init__(message=message, error_code=error_code, status_code=409)


# ── Exception Handlers ────────────────────────────────────────────────────────

def register_exception_handlers(app: FastAPI) -> None:
    """
    Register all custom exception handlers on the FastAPI app.
    Called once in main.py during app initialization.
    """

    @app.exception_handler(DesignMirrorException)
    async def designmirror_exception_handler(
        request: Request, exc: DesignMirrorException
    ) -> JSONResponse:
        """Handle all DesignMirror custom exceptions."""
        logger.warning(
            "Error {code} on {method} {path}: {msg}",
            code=exc.error_code,
            method=request.method,
            path=request.url.path,
            msg=exc.message,
        )
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "detail": exc.message,
                "error_code": exc.error_code,
            },
        )

    @app.exception_handler(HTTPException)
    async def http_exception_handler(
        request: Request, exc: HTTPException
    ) -> JSONResponse:
        """Normalize FastAPI's built-in HTTPException to our format."""
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "detail": exc.detail,
                "error_code": "HTTP_ERROR",
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(
        request: Request, exc: Exception
    ) -> JSONResponse:
        """
        Catch-all for unexpected errors.

        SECURITY: We never expose internal error details to the client.
        The real error is logged server-side for debugging.
        """
        logger.exception(
            "Unhandled error on {method} {path}",
            method=request.method,
            path=request.url.path,
        )
        return JSONResponse(
            status_code=500,
            content={
                "detail": "An internal error occurred. Please try again later.",
                "error_code": "INTERNAL_ERROR",
            },
        )

