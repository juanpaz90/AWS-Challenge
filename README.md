# AWS DevOps Challenge — Notes API on Kubernetes

Deploy a sample API (multiple replicas) and its PostgreSQL database with persistent storage on Kubernetes, fully defined as code with Terraform and Helm. The API is reachable from outside; the database is not.

**Local-first, cloud-ready:** everything runs on a Terraform-managed `kind` cluster, and the same charts and platform layer are reused on AWS EKS.

> Status: 🚧 in progress — see the [milestone checklist](docs/project-plan.md#11-milestone-checklist).

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
| [Project plan](docs/project-plan.md) | Phases, tech stack, Terraform design |
| [User story](docs/user-story.md) | Epic, stories S1–S11, acceptance criteria |
| [Architecture](docs/architecture.md) | Topology, network security, Terraform layout, local → AWS |
| [ADRs](docs/adr/README.md) | Architecture decisions and trade-offs |
| [SLOs](docs/slo.md) | Availability and latency objectives, error budgets |
| [Runbook](docs/runbook.md) | Alert responses and operational procedures |
| [GenAI](docs/genai.md) | How AI was used, validated and corrected |
| [CLAUDE.md](CLAUDE.md) | Rules for the AI assistant |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow, Conventional Commits, hooks |

## Prerequisites

| Tool | Version | Used for |
|---|---|---|
| Docker | 29.7.2 | kind nodes, image builds |
| terraform | 1.16.0 (≥ 1.10 required) | IaC |
| helm | 4.3.0 | charts, `helm lint` |
| task (go-task) | 3.54.0 | task runner |
| pre-commit | 4.6.2 | git hooks |
| tflint | 0.64.0 | Terraform linting |
| trivy | 0.75.0 | IaC and image scanning |
| hadolint | 2.15.1 | Dockerfile linting |
| kubeconform | 0.8.0 | manifest validation |
| kind · kubectl · terraform-docs · helm-docs · checkov · k6 · infracost | _tbd_ | later phases |

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
