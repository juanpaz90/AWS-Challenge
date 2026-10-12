"""Prometheus metrics and the HTTP middleware that records them and the access log.

Metric names follow the conventions used in docs/slo.md. The `handler` label is the route
template (e.g. /notes/{note_id}), never the raw path, to keep label cardinality bounded.
"""

import logging
import time
import uuid

from fastapi import Request, Response
from prometheus_client import Counter, Gauge, Histogram
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

REQUESTS = Counter(
    "http_requests_total", "HTTP requests processed", ["method", "handler", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "handler"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0, 2.5, 5.0),
)
IN_PROGRESS = Gauge("http_requests_in_progress", "HTTP requests in progress", ["method"])

# Probe and scrape traffic is logged at DEBUG so it does not drown application logs.
QUIET_PATHS = frozenset({"/healthz", "/readyz", "/metrics"})

access_logger = logging.getLogger("notes_api.access")


def route_template(request: Request) -> str:
    """The matched route's path template; the router stores the route in the scope."""
    return getattr(request.scope.get("route"), "path", "unmatched")


class ObservabilityMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, pod_name: str) -> None:
        super().__init__(app)
        self.pod_name = pod_name

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        request_id = request.headers.get("x-request-id") or uuid.uuid4().hex
        method = request.method
        status = 500
        start = time.perf_counter()
        IN_PROGRESS.labels(method).inc()
        try:
            response = await call_next(request)
            status = response.status_code
        finally:
            elapsed = time.perf_counter() - start
            handler = route_template(request)  # only known once routing has happened
            IN_PROGRESS.labels(method).dec()
            REQUESTS.labels(method, handler, str(status)).inc()
            LATENCY.labels(method, handler).observe(elapsed)
            access_logger.log(
                logging.DEBUG if request.url.path in QUIET_PATHS else logging.INFO,
                "%s %s %s",
                method,
                request.url.path,
                status,
                extra={
                    "request_id": request_id,
                    "method": method,
                    "path": request.url.path,
                    "status": status,
                    "duration_ms": round(elapsed * 1000, 2),
                    "client": request.client.host if request.client else None,
                },
            )
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Pod-Name"] = self.pod_name
        return response
