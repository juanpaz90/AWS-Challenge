# Local application stack. image_tag / image_digest are passed by `task apps:up`.
# Versions verified on 2026-10-11.
cnpg_cluster_chart_version = "0.9.0"

# PostgreSQL 18.6 — same version as the Docker Compose smoke stack.
postgres_image        = "ghcr.io/cloudnative-pg/postgresql:18.6-minimal-trixie@sha256:37ade18dbdddba430858c72725aceeec66f33fa5333e82ea1df4942f6c1c83a3"
database_storage_size = "2Gi"

labels = {
  project     = "aws-challenge"
  environment = "local"
}
