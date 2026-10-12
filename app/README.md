# Notes API

A small FastAPI service with CRUD on notes, backed by PostgreSQL. Story S1.

## Endpoints

| Path | Purpose |
|---|---|
| `GET /` | Service info: message, version, pod name |
| `GET /healthz` | Liveness: the process is serving (no database check) |
| `GET /readyz` | Readiness: `200` only when the database answers `SELECT 1`, else `503` |
| `GET /metrics` | Prometheus metrics |
| `GET /notes?limit=&offset=` | List notes (limit 1–100, default 20) |
| `POST /notes` | Create `{"title": "...", "content": "..."}` |
| `GET /notes/{id}` | Read one |
| `PATCH /notes/{id}` | Partial update |
| `DELETE /notes/{id}` | Delete |

Every response carries `X-Pod-Name` and `X-Request-ID` headers. An incoming `X-Request-ID` is propagated.

## Configuration

All configuration comes from environment variables. Nothing secret has a default.

| Variable | Default | Notes |
|---|---|---|
| `DATABASE_URL` | — | Full URL; takes precedence over `DB_*`. `postgresql://` is rewritten to the psycopg 3 driver. |
| `DB_HOST` / `DB_PORT` / `DB_NAME` / `DB_USER` / `DB_PASSWORD` | `localhost` / `5432` / `app` / `app` / empty | Match the keys of the CloudNativePG `<cluster>-app` Secret |
| `DB_POOL_SIZE` / `DB_MAX_OVERFLOW` | `5` / `5` | Per pod |
| `APP_MESSAGE` | `Hello from the Notes API` | Returned by `GET /`; used to demo config changes |
| `APP_VERSION` | `dev` | Set to the git SHA by the image build |
| `POD_NAME` | hostname | Inject from the Downward API on Kubernetes |
| `LOG_LEVEL` | `INFO` | Access logs for probes and `/metrics` are at `DEBUG` |
| `PORT` | `8000` | |
| `SHUTDOWN_TIMEOUT_SECONDS` | `20` | Max time to drain in-flight requests after `SIGTERM` |

## Observability

- **Logs:** one JSON object per line on stdout, with `ts`, `level`, `logger`, `message`, `pod`. Access lines add `request_id`, `method`, `path`, `status`, `duration_ms`.
- **Metrics:**
  - `http_requests_total{method,handler,status}`
  - `http_request_duration_seconds{method,handler}` (histogram)
  - `http_requests_in_progress{method}`

  `handler` is the route template (`/notes/{note_id}`), so cardinality stays bounded. One uvicorn worker per container; scale with replicas, not workers.

## Migrations

Schema changes are Alembic migrations in `migrations/versions/`. They are **never** run at application startup: with several replicas that would race. Run them as a separate step, which becomes a Helm pre-install/pre-upgrade Job in Phase 7:

```bash
alembic upgrade head          # inside the image: same env vars as the API
alembic upgrade head --sql    # print the SQL without connecting
```

## Graceful shutdown

On `SIGTERM`, uvicorn stops accepting connections, waits up to `SHUTDOWN_TIMEOUT_SECONDS` for in-flight requests, then the lifespan hook disposes the connection pool. On Kubernetes the chart adds a short `preStop` sleep so the endpoint is removed from the Service before shutdown starts.

## Local development

```bash
uv sync                  # Python 3.14 + locked dependencies
uv run pytest            # unit + migration tests (SQLite, no Docker needed)
uv run ruff check . && uv run ruff format --check .
```

Full stack with PostgreSQL, from the repository root:

```bash
task compose:up          # build image, start db → migrate → api on http://127.0.0.1:8080
task compose:smoke       # end-to-end checks, including data surviving restarts
task compose:down
```

## Image

Multi-stage `Dockerfile`: dependencies are installed with `uv` from `uv.lock` in a builder stage, then only the virtualenv and migrations are copied into a `python:<version>-slim` runtime that runs as UID `10001` and works with a read-only root filesystem. Base images are pinned by version **and** digest.

## Security scan

`task scan` runs `hadolint` on the Dockerfile and `trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`, so the build fails on any HIGH/CRITICAL vulnerability that has a fix available.

| Date | Image | Fixable HIGH/CRITICAL | Unfixed HIGH/CRITICAL | Notes |
|---|---|---|---|---|
| 2026-10-11 | `python:3.14.8-slim-trixie` base, ~67 MB compressed | **0** | 44 HIGH, 0 CRITICAL (Debian 13.7 packages) | First scan found 4 fixable HIGH findings in `pip`'s vendored `urllib3`, `msgpack` and `setuptools`; fixed by removing pip from the runtime image. |

**Accepted risk:** the unfixed findings are in Debian base packages with no patched version published yet. They are not gated (`--ignore-unfixed`) and are re-checked on every base-image bump. If the count matters more than image familiarity, the next step is a distroless or Chainguard Python base.
