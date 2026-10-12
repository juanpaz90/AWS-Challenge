# syntax=docker/dockerfile:1
# Notes API image. Base images are pinned by version and multi-arch index digest.
ARG PYTHON_IMAGE=python:3.14.8-slim-trixie@sha256:a2b82f3c48559aa0a8446d9af49826b6e2b2016f4cd2afabfe6013ec53729170
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.12.24@sha256:3af4716e991d6956a41e573eab705d0ee08500cd829ed30293eb8472f372c65a

FROM ${UV_IMAGE} AS uv

# --- Builder: resolve the locked dependencies into a self-contained virtualenv ---------------
FROM ${PYTHON_IMAGE} AS builder
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /src

# Dependencies first, so this layer is cached until uv.lock changes.
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

COPY README.md ./
COPY src ./src
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-editable

# --- Runtime: no build tools, no package manager use, non-root ----------------------------
FROM ${PYTHON_IMAGE} AS runtime

ARG VERSION=dev
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="notes-api" \
      org.opencontainers.image.description="Sample Notes API (FastAPI + PostgreSQL)" \
      org.opencontainers.image.source="https://github.com/juanpaz90/AWS-Challenge" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION="${VERSION}" \
    PORT=8000

# pip is not needed at runtime (dependencies come from the builder's venv) and its vendored
# libraries carry their own CVEs, so the package manager is removed from the final image.
RUN python -m pip uninstall --yes pip \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --home-dir /nonexistent \
      --shell /usr/sbin/nologin app

WORKDIR /app
# Owned by root and not writable by the app user: works with a read-only root filesystem.
COPY --from=builder /app/.venv /app/.venv
COPY alembic.ini ./
COPY migrations ./migrations

USER 10001:10001
EXPOSE 8000
STOPSIGNAL SIGTERM
CMD ["python", "-m", "notes_api"]
