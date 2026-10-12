# AWS DevOps Challenge — Notes API on Kubernetes

[![CI](https://github.com/juanpaz90/AWS-Challenge/actions/workflows/ci.yml/badge.svg)](https://github.com/juanpaz90/AWS-Challenge/actions/workflows/ci.yml)

Deploy a sample API (multiple replicas) and its PostgreSQL database with persistent storage on Kubernetes, fully defined as code with Terraform and Helm. The API is reachable from outside; the database is not.

**Local-first, cloud-ready:** everything runs on a Terraform-managed `kind` cluster, and the same charts and platform layer are reused on AWS EKS.

> Status: ✅ Milestone 1 (core, local) done — `task up` builds everything from zero and `task test` proves all 10 functional checks. Phase 10 (observability as code) done. See the [milestone checklist](docs/project-plan.md#11-milestone-checklist).

## Quick start

```bash
task up      # cluster → platform → apps
task test    # validation suite
task down    # apps → platform → cluster
```

Then open:

- API: <https://api.localtest.me>
- Grafana: <https://grafana.localtest.me>

## Architecture at a glance

```
Client ─► Envoy Gateway (TLS) ─► Notes API (Deployment + HPA) ─► PostgreSQL (CloudNativePG + PVC)
                                         default-deny NetworkPolicies · PSA restricted
```

Full diagrams in [docs/architecture.md](docs/architecture.md).

## Documentation

| Document | Purpose |
|---|---|
| [Operator guide](docs/operator-guide.md) | Step by step: deploy, use, consoles, test, debug, tear down |
| [Project plan](docs/project-plan.md) | Phases, tech stack, Terraform design |
| [User story](docs/user-story.md) | Epic, stories S1–S11, acceptance criteria |
| [Architecture](docs/architecture.md) | Topology, network security, Terraform layout, local → AWS |
| [ADRs](docs/adr/README.md) | Architecture decisions and trade-offs |
| [SLOs](docs/slo.md) | Availability and latency objectives, error budgets |
| [Observability](observability/README.md) | Dashboards, alert and SLO rules as code |
| [Runbook](docs/runbook.md) | Alert responses and operational procedures |
| [GenAI](docs/genai.md) | How AI was used, validated and corrected |
| [CLAUDE.md](CLAUDE.md) | Rules for the AI assistant |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow, Conventional Commits, hooks |

## CI/CD

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every pull request and every push to `main` (docs-only changes are skipped):

| Job | What it runs |
|---|---|
| `lint` | `pre-commit run --all-files` — Terraform fmt/validate/tflint/trivy/docs, hadolint, yamllint, actionlint, helm lint + kubeconform, chart tests, helm-docs, promtool rule tests, ruff, gitleaks |
| `app` | `pytest` (unit + Alembic migration tests) |
| `image` | `task scan` — reproducible build, hadolint, `trivy image` (fails on fixable HIGH/CRITICAL) |
| `e2e` | ephemeral kind cluster on the runner: `task up` → `task test` → `task obs:check` → `task down` (diagnostics uploaded on failure) |
| `release` | `main` only, after `e2e`: push `ghcr.io/<owner>/notes-api:<sha>` with SBOM + SLSA provenance (signed attestation when the repo is public) |

CI uses the same pinned tool versions as below ([`setup-toolchain`](.github/actions/setup-toolchain/action.yml), checksum-verified downloads), actions are pinned to commit SHAs, and the token is read-only outside `release`. Dependabot keeps actions, base images, Python dependencies and Terraform providers current. AWS access (Phase 13) will use GitHub OIDC — no static keys.

## Prerequisites

| Tool | Version | Used for |
|---|---|---|
| Docker | 29.7.2 (Colima) | kind nodes, image builds |
| docker-buildx · docker compose | 0.38.0 · 5.5.1 | BuildKit builds, local smoke stack |
| uv | 0.12.24 | Python 3.14 + locked dependencies for the Notes API |
| terraform | 1.16.0 (≥ 1.10 required) | IaC |
| helm | 4.3.0 | charts, `helm lint` |
| task (go-task) | 3.54.0 | task runner |
| pre-commit | 4.6.2 | git hooks |
| tflint | 0.64.0 | Terraform linting |
| trivy | 0.75.0 | IaC and image scanning |
| hadolint | 2.15.1 | Dockerfile linting |
| kubeconform | 0.8.0 | manifest validation |
| kubectl | 1.35.9 | must stay within one minor of the cluster (1.35) |
| kind (CLI, optional) | 0.33.0 | inspection only — clusters are created by Terraform (embedded kind v0.31.0) |
| terraform-docs | 0.24.0 | module READMEs |
| helm-docs | 1.14.2 | chart README |
| k6 | 2.3.0 | load tests (HPA demo) |
| actionlint · shellcheck | 1.7.12 · 0.11.0 | GitHub Actions linting |
| checkov · infracost | _tbd_ | later phases |

yamllint, gitleaks and the Conventional Commits checker are installed automatically by pre-commit.

Docker needs ≥ 8 GB RAM and ≥ 4 CPUs once observability runs. Run `task setup` once after cloning to install the git hooks.

## Repository layout

```
app/            Notes API source + Dockerfile
charts/         Notes API Helm chart
infra/          Terraform modules, bootstrap and environments (local, dev, prod)
gitops/         Argo CD applications (bonus)
observability/  Dashboards, alert rules, SLO rules
tests/          Smoke / e2e scripts
scripts/        Helper scripts used by hooks and tasks
docs/           Plan, user story, ADRs, architecture, runbook, GenAI log
```
