"""Application factory."""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from notes_api.api import notes, system
from notes_api.config import Settings, get_settings
from notes_api.db import create_db_engine, create_session_factory
from notes_api.metrics import ObservabilityMiddleware

logger = logging.getLogger(__name__)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        engine = create_db_engine(settings)
        app.state.engine = engine
        app.state.session_factory = create_session_factory(engine)
        logger.info("startup complete", extra={"version": settings.app_version})
        yield
        # Runs after uvicorn has stopped accepting connections and drained in-flight requests.
        engine.dispose()
        logger.info("shutdown complete")

    app = FastAPI(title="Notes API", version=settings.app_version, lifespan=lifespan)
    app.state.settings = settings
    app.add_middleware(ObservabilityMiddleware, pod_name=settings.pod_name)
    app.include_router(system)
    app.include_router(notes)
    return app
