from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect

from notes_api.config import get_settings

APP_DIR = Path(__file__).resolve().parents[1]


def test_migrations_upgrade_and_downgrade(tmp_path, monkeypatch):
    db_file = tmp_path / "migrations.db"
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{db_file}")
    get_settings.cache_clear()
    config = Config(str(APP_DIR / "alembic.ini"))

    try:
        command.upgrade(config, "head")
        engine = create_engine(f"sqlite:///{db_file}")
        columns = {c["name"] for c in inspect(engine).get_columns("notes")}
        assert columns == {"id", "title", "content", "created_at", "updated_at"}

        command.downgrade(config, "base")
        assert "notes" not in inspect(engine).get_table_names()
        engine.dispose()
    finally:
        get_settings.cache_clear()
