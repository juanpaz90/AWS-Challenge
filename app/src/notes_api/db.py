"""Database engine and session handling."""

from collections.abc import Iterator

from fastapi import Request
from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from notes_api.config import Settings


def create_db_engine(settings: Settings) -> Engine:
    url = settings.sqlalchemy_url()
    if str(url).startswith("sqlite"):
        # Used by the unit tests only: a single shared in-memory connection.
        return create_engine(url, connect_args={"check_same_thread": False}, poolclass=StaticPool)
    return create_engine(
        url,
        pool_pre_ping=True,
        pool_size=settings.db_pool_size,
        max_overflow=settings.db_max_overflow,
        connect_args={"connect_timeout": 5, "application_name": "notes-api"},
    )


def create_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(engine, expire_on_commit=False)


def get_session(request: Request) -> Iterator[Session]:
    with request.app.state.session_factory() as session:
        yield session
