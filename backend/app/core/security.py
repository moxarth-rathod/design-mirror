"""
DesignMirror AI — Security Utilities
======================================

This module handles the three pillars of our security strategy:

1. PASSWORD HASHING (Bcrypt)
   ─────────────────────────
   We NEVER store plaintext passwords. Bcrypt is a one-way hash — even if the
   database is stolen, attackers can't reverse-engineer the password.
   The "cost factor" (rounds=12) makes each hash take ~250ms, which is fast
   enough for login but painfully slow for brute-force attacks.

2. JWT TOKENS (python-jose)
   ────────────────────────
   After login, the user gets a signed token containing their user ID.
   The token is like a "VIP wristband" — they show it on every request
   instead of sending their password each time.
   • Access Token:  Short-lived (15 min). Used for API calls.
   • Refresh Token: Long-lived (7 days). Used to get a new access token.

3. AES-256-GCM ENCRYPTION (data at rest)
   ──────────────────────────────────────
   Sensitive data (room scans) is encrypted before being stored in MongoDB.
   Even if someone gets raw database access, the data is unreadable without
   the encryption key (stored in environment variables, never in code).
"""

import os
from datetime import datetime, timedelta, timezone

from jose import jwt, JWTError
from passlib.context import CryptContext
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.config import settings
from app.core.logging import logger


# ── Password Hashing ──────────────────────────────────────────────────────────

# CryptContext is Passlib's "smart" hasher. It auto-detects the hash format
# and can gracefully upgrade old hashes when users log in.
pwd_context = CryptContext(
    schemes=["bcrypt"],
    deprecated="auto",          # Auto-upgrade older hash versions
    bcrypt__rounds=12,          # Cost factor: 2^12 = 4096 iterations
)


def hash_password(plain_password: str) -> str:
    """Hash a plaintext password using Bcrypt."""
    return pwd_context.hash(plain_password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a plaintext password against a Bcrypt hash.

    SECURITY: This uses constant-time comparison internally to prevent
    'timing attacks' — where an attacker measures response time to
    guess how many characters matched.
    """
    return pwd_context.verify(plain_password, hashed_password)


# ── JWT Token Creation ─────────────────────────────────────────────────────────

def create_access_token(subject: str, extra_claims: dict | None = None) -> str:
    """
    Create a short-lived JWT access token.

    Args:
        subject: The user ID (stored as 'sub' claim in the token).
        extra_claims: Optional additional data to embed in the token.

    Returns:
        Encoded JWT string.

    HOW JWT WORKS (simplified):
        Token = base64(header) + "." + base64(payload) + "." + signature
        The signature is created using our SECRET_KEY, so only WE can create
        valid tokens. If anyone tampers with the payload, the signature won't
        match and the token is rejected.
    """
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload = {
        "sub": subject,
        "exp": expire,
        "type": "access",
    }
    if extra_claims:
        payload.update(extra_claims)

    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token(subject: str) -> str:
    """
    Create a long-lived JWT refresh token.

    The refresh token is used to obtain new access tokens without
    requiring the user to log in again.
    """
    expire = datetime.now(timezone.utc) + timedelta(
        days=settings.JWT_REFRESH_TOKEN_EXPIRE_DAYS
    )
    payload = {
        "sub": subject,
        "exp": expire,
        "type": "refresh",
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_token(token: str) -> dict:
    """
    Decode and validate a JWT token.

    Raises:
        JWTError: If the token is expired, tampered with, or invalid.

    SECURITY: python-jose automatically checks:
        1. Signature validity (was it signed with our key?)
        2. Expiration (is it still valid?)
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
        )
        return payload
    except JWTError as e:
        logger.warning("JWT decode failed: {}", str(e))
        raise


# ── AES-256-GCM Encryption ────────────────────────────────────────────────────

def _get_aes_key() -> bytes:
    """
    Derive the AES-256 encryption key from the environment variable.

    The key must be exactly 32 bytes (256 bits) for AES-256.
    We store it as a hex string in .env and convert to bytes here.
    """
    key_hex = settings.AES_ENCRYPTION_KEY
    try:
        key_bytes = bytes.fromhex(key_hex)
        if len(key_bytes) != 32:
            raise ValueError(f"AES key must be 32 bytes, got {len(key_bytes)}")
        return key_bytes
    except ValueError:
        # If the key isn't valid hex, generate a warning.
        # In production, this should crash the app.
        logger.error(
            "AES_ENCRYPTION_KEY is not valid 32-byte hex. "
            "Encryption/decryption will fail."
        )
        raise


def encrypt_data(plaintext: bytes) -> bytes:
    """
    Encrypt data using AES-256-GCM.

    Returns: nonce (12 bytes) + ciphertext + tag (16 bytes)

    GCM mode provides both:
      • Confidentiality — data is encrypted
      • Integrity — any tampering is detected (via the authentication tag)
    """
    key = _get_aes_key()
    nonce = os.urandom(12)  # 96-bit nonce (unique per encryption)
    aesgcm = AESGCM(key)
    ciphertext = aesgcm.encrypt(nonce, plaintext, None)
    return nonce + ciphertext  # Prepend nonce for decryption


def decrypt_data(encrypted: bytes) -> bytes:
    """
    Decrypt AES-256-GCM encrypted data.

    Expects: nonce (first 12 bytes) + ciphertext + tag
    """
    key = _get_aes_key()
    nonce = encrypted[:12]
    ciphertext = encrypted[12:]
    aesgcm = AESGCM(key)
    return aesgcm.decrypt(nonce, ciphertext, None)

