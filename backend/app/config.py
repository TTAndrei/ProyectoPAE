"""Application configuration and constants."""
import os

# JWT
SECRET_KEY: str = os.getenv("SECRET_KEY", "pae_dev_secret_change_in_production")
ALGORITHM: str = "HS256"
ACCESS_TOKEN_EXPIRE_HOURS: int = 8

# Database
DB_PATH: str = os.getenv("DB_PATH", "pae.db")

# CORS
CORS_ORIGINS: list[str] = os.getenv(
    "CORS_ORIGINS", "http://localhost:3000"
).split(",")
