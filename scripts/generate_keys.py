"""
DesignMirror AI — Key Generation Script
=========================================

Run this script to generate secure random keys for your .env file:

    python scripts/generate_keys.py

It will output:
  • A 64-character JWT secret key
  • A 32-byte AES-256 encryption key (as hex)

NEVER commit these keys to Git. They belong ONLY in .env (which is gitignored).
"""

import secrets


def main():
    print("=" * 60)
    print("  DesignMirror AI — Secure Key Generator")
    print("=" * 60)
    print()

    # JWT Secret Key — used to sign access and refresh tokens
    jwt_secret = secrets.token_urlsafe(48)  # ~64 chars
    print(f"JWT_SECRET_KEY={jwt_secret}")
    print()

    # AES-256 Encryption Key — must be exactly 32 bytes (64 hex chars)
    aes_key = secrets.token_hex(32)  # 32 bytes = 64 hex chars
    print(f"AES_ENCRYPTION_KEY={aes_key}")
    print()

    print("─" * 60)
    print("Copy these values into your .env file.")
    print("NEVER share or commit these keys.")
    print("─" * 60)


if __name__ == "__main__":
    main()

