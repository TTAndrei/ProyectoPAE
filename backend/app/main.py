"""FastAPI application factory."""
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import CORS_ORIGINS
from app.database import init_db
from app.routers.auth import router as auth_router
from app.routers.drivers import router as drivers_router
from app.routers.orders import router as orders_router
from app.routers.ws import router as ws_router

STATIC_DIR = Path(__file__).parent.parent / "static"


def create_app() -> FastAPI:
    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        init_db()
        yield

    app = FastAPI(
        title="PAE – Delivery Route Manager",
        description=(
            "Last-mile delivery route management: real-time driver location, "
            "pickup notifications, and route optimisation."
        ),
        version="1.0.0",
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(auth_router)
    app.include_router(drivers_router)
    app.include_router(orders_router)
    app.include_router(ws_router)

    @app.get("/health")
    def health():
        return {"status": "ok"}

    # Serve the frontend
    if STATIC_DIR.exists():
        app.mount("/", StaticFiles(directory=str(STATIC_DIR), html=True), name="static")

    return app


app = create_app()
