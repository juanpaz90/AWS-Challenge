"""Runtime configuration, read from environment variables only."""

import socket
from functools import lru_cache

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings
from sqlalchemy.engine import URL


class Settings(BaseSettings):
    """Application settings.

    Database credentials come either from DATABASE_URL or from the individual DB_* variables,
    which map one-to-one onto the keys of the CloudNativePG-generated `<cluster>-app` Secret.
    """

    app_message: str = "Hello from the Notes API"
    app_version: str = "dev"
    pod_name: str = Field(default_factory=socket.gethostname)
    log_level: str = "INFO"

    host: str = "0.0.0.0"  # noqa: S104 - must listen on all interfaces inside a container
    port: int = 8000
    shutdown_timeout_seconds: int = 20

    database_url: SecretStr | None = None
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "app"
    db_user: str = "app"
    db_password: SecretStr = SecretStr("")
    db_pool_size: int = 5
    db_max_overflow: int = 5

    def sqlalchemy_url(self) -> URL | str:
        """Return the SQLAlchemy URL, always using the psycopg 3 driver for PostgreSQL."""
        if self.database_url is not None:
            url = self.database_url.get_secret_value()
            if url.startswith(("postgresql://", "postgres://")):
                url = "postgresql+psycopg://" + url.split("://", 1)[1]
            return url
        return URL.create(
            "postgresql+psycopg",
            username=self.db_user,
            password=self.db_password.get_secret_value(),
            host=self.db_host,
            port=self.db_port,
            database=self.db_name,
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
