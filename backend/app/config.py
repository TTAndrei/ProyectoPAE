"""Configuración y constantes de la aplicación PAE."""
import os

# ── Autenticación JWT ──────────────────────────────────────────────────────────
# Clave secreta para firmar los tokens. ¡Cambiar en producción!
CLAVE_SECRETA: str = os.getenv("SECRET_KEY", "pae_dev_secret_cambiar_en_produccion")
# Algoritmo de cifrado para JWT
ALGORITMO: str = "HS256"
# Número de horas que dura una sesión antes de expirar
HORAS_EXPIRACION_TOKEN: int = 8

# ── Base de datos ──────────────────────────────────────────────────────────────
# Ruta al archivo SQLite (se crea automáticamente si no existe)
RUTA_BD: str = os.getenv("DB_PATH", "pae.db")

# ── CORS ───────────────────────────────────────────────────────────────────────
# Orígenes permitidos para peticiones cross-origin (separados por coma)
ORIGENES_CORS: list[str] = [
    origen.strip()
    for origen in os.getenv(
        "CORS_ORIGINS",
        "http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000,http://127.0.0.1:8080",
    ).split(",")
    if origen.strip()
]

# Regex opcional para permitir orígenes dinámicos de desarrollo local.
# Por defecto acepta localhost/127.0.0.1 con o sin puerto (Flutter web usa
# puertos efímeros durante `flutter run`).
REGEX_ORIGEN_CORS: str = os.getenv(
    "CORS_ORIGIN_REGEX",
    r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
)
