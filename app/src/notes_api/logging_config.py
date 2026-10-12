"""Structured JSON logging to stdout, one object per line, tagged with the pod name."""

import json
import logging
import sys
from datetime import UTC, datetime

# Attributes passed via `extra=` that are copied into the JSON payload.
EXTRA_FIELDS = (
    "request_id",
    "method",
    "path",
    "status",
    "duration_ms",
    "client",
    "note_id",
    "version",
)


class JsonFormatter(logging.Formatter):
    def __init__(self, pod_name: str) -> None:
        super().__init__()
        self.pod_name = pod_name

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname.lower(),
            "logger": record.name,
            "message": record.getMessage(),
            "pod": self.pod_name,
        }
        for field in EXTRA_FIELDS:
            if hasattr(record, field):
                payload[field] = getattr(record, field)
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging(level: str, pod_name: str) -> None:
    """Route every logger (including uvicorn's and alembic's) through one JSON handler."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter(pod_name))

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())

    for name in ("uvicorn", "uvicorn.error", "alembic"):
        logger = logging.getLogger(name)
        logger.handlers = []
        logger.propagate = True
    # Access lines are emitted by our own middleware, with route and latency.
    logging.getLogger("uvicorn.access").disabled = True
