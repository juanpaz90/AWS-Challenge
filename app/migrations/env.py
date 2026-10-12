"""Alembic environment: reuses the application's settings and JSON logging."""

from alembic import context
from sqlalchemy import create_engine, pool

from notes_api.config import get_settings
from notes_api.logging_config import configure_logging
from notes_api.models import Base

settings = get_settings()
configure_logging(settings.log_level, settings.pod_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Emit SQL to stdout (`alembic upgrade head --sql`) without connecting."""
    context.configure(
        url=str(settings.sqlalchemy_url()),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    engine = create_engine(settings.sqlalchemy_url(), poolclass=pool.NullPool)
    with engine.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
    engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
