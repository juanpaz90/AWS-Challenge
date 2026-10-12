import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr

from notes_api.config import Settings
from notes_api.main import create_app
from notes_api.models import Base


@pytest.fixture
def settings() -> Settings:
    return Settings(
        database_url=SecretStr("sqlite://"),
        pod_name="test-pod",
        app_message="hello from tests",
        app_version="test",
    )


@pytest.fixture
def client(settings: Settings):
    app = create_app(settings)
    with TestClient(app) as test_client:
        # Unit tests use in-memory SQLite; real schemas are created by Alembic.
        Base.metadata.create_all(app.state.engine)
        yield test_client
