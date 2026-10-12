"""Entrypoint: `python -m notes_api`.

uvicorn handles SIGTERM gracefully: it stops accepting new connections, waits up to
SHUTDOWN_TIMEOUT_SECONDS for in-flight requests, then runs the lifespan shutdown.
"""

import uvicorn

from notes_api.config import get_settings
from notes_api.logging_config import configure_logging
from notes_api.main import create_app


def main() -> None:
    settings = get_settings()
    configure_logging(settings.log_level, settings.pod_name)
    uvicorn.run(
        create_app(settings),
        host=settings.host,
        port=settings.port,
        log_config=None,  # keep the JSON logging configured above
        access_log=False,  # access lines come from ObservabilityMiddleware
        server_header=False,
        timeout_graceful_shutdown=settings.shutdown_timeout_seconds,
    )


if __name__ == "__main__":
    main()
