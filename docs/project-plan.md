# AWS DevOps Technical Exercise — Project Plan

> **Goal:** Deploy a sample API (multiple replicas) and its PostgreSQL database with persistent storage on Kubernetes, fully defined as code (Terraform + Helm), with the API reachable from outside and the database not.
> **Strategy:** **Local-first, cloud-ready.** Build and prove everything on a `kind` cluster managed by Terraform, then reuse the same modules, charts and platform layer on AWS EKS.
> **Rule for the whole project:** no manual resource creation. Every resource comes from Terraform, Helm or GitOps.

---

## Table of contents

1. [Guiding principles](#1-guiding-principles)
2. [Prerequisites](#2-prerequisites)
3. [Target architecture](#3-target-architecture)
4. [Tech stack](#4-tech-stack)
5. [Terraform design](#5-terraform-design)
6. [Repository structure](#6-repository-structure)
7. [Execution plan (ordered phases)](#7-execution-plan-ordered-phases)
8. [AI-assisted IaC workflow (Claude)](#8-ai-assisted-iac-workflow-claude)
9. [Definition of Done (global)](#9-definition-of-done-global)
10. [Risks and mitigations](#10-risks-and-mitigations)
11. [Milestone checklist](#11-milestone-checklist)

---

## 1. Guiding principles

- **The user story drives the work.** Every phase maps to a story with acceptance criteria.
- **Local ≈ cloud.** The same Helm charts and platform layer run on kind and on EKS; only the cluster layer changes.
- **Everything as code.** This covers infrastructure, platform add-ons, dashboards, alerts and policies.
- **Security by default.** This means least privilege, default-deny networking, non-root containers, no secrets in Git or Terraform state, and pinned versions.
- **Small, verifiable increments.** Each slice is linted, scanned, deployed and tested before moving on.
- **Reproducibility.** One command each to bring up, test and tear down an environment.
- **Evidence over claims.** Keep prompt logs, separate AI-output and correction commits, and scripted tests.

---

## 2. Prerequisites

### 2.1 Hardware and accounts

| Item | Requirement |
|---|---|
| RAM | ≥ 16 GB recommended (allocate ≥ 8 GB to Docker once observability runs) |
| Disk | ~30 GB free |
| GitHub | New repository (this is what the panel reviews), clean commit history from day one |
| AWS account | Only needed for the cloud phases. **Create a billing budget and alert first.** |

### 2.2 Tooling

| Purpose | Tools |
|---|---|
| Containers | Docker Desktop / Rancher Desktop / Colima |
| Local Kubernetes | `kind`, `kubectl`, `k9s` (optional, useful for demos) |
| Packaging | `helm` v3, `helm-docs`, (optional) `kustomize` |
| IaC | `terraform` (or OpenTofu), `tflint` (+ AWS ruleset), `terraform-docs` |
| Security / compliance | `trivy` and/or `checkov`, `hadolint` |
| Validation | `kubeconform`, `yamllint`, `pre-commit` |
| Cost | `infracost` |
| Testing | `curl`/`httpie`, `jq`, `k6` (load test for HPA demo) |
| Task runner | `Taskfile` or `make` |
| Cloud (later) | AWS CLI v2, `eksctl` (troubleshooting only, never to create resources) |
| AI assistant | Claude Code (CLI/IDE), optionally a Terraform MCP server for current provider docs |

### 2.3 Decisions to confirm before building

1. Operating system (affects kind networking and Docker memory settings).
2. API language: **Python / FastAPI** (assumed).
3. Argo CD from the start or later (recommended: **later**, as an evolution step).
4. Verify current versions and status of every chart, provider and project on Artifact Hub and the Terraform Registry before pinning, especially ingress-nginx (retirement announced), the Bitnami catalog (distribution changes) and Promtail (deprecated in favour of Alloy).

---

## 3. Target architecture

### 3.1 Local topology

```
Client (browser / curl)
  │  api.localtest.me / grafana.localtest.me  (resolve to 127.0.0.1)
  ▼
Docker host (laptop) ── all created by Terraform ─────────────────────────────┐
│                                                                            │
│  ┌──────────── kind cluster (1 control plane + 2 workers) ─────────────┐   │
│  │  host 80/443 ─► extraPortMappings ─► Envoy Gateway (NodePort)       │   │
│  │                                        │ HTTPRoute (TLS: cert-mgr)  │   │
│  │                                        ▼                            │   │
│  │                              notes-api Service (ClusterIP)          │   │
│  │                              Notes API pods (Deployment + HPA)      │   │
│  │                                        │ 5432 only (NetworkPolicy)  │   │
│  │                                        ▼                            │   │
│  │                              PostgreSQL (CloudNativePG) + PVC       │   │
│  │                                                                     │   │
│  │  Platform: Calico CNI · cert-manager · metrics-server · CNPG operator│   │
│  │  Observability: Prometheus · Alertmanager · Grafana · Loki · Alloy  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│  Local registry container (localhost:5001) ─► image pulls by kind nodes    │
└────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Networking and security rules (core requirement)

- **API is public:** exposed only through Envoy Gateway (`Gateway` + `HTTPRoute`).
- **DB is private:** ClusterIP only, no Ingress, NodePort or LoadBalancer.
- **NetworkPolicies in the `notes` namespace:**
  - Default deny for ingress and egress.
  - Allow gateway → API (app port).
  - Allow API → DB (5432).
  - Allow CNPG operator → DB (management).
  - Allow monitoring → metrics ports.
  - Allow DNS egress to `kube-system`.
- **Namespaces:** `gateway`, `cert-manager`, `cnpg-system`, `monitoring`, `calico-system`, `notes` (app + DB).
- **Pod Security Admission:**
  - `notes` uses `restricted`.
  - Platform namespaces get only the level they need, with documented exceptions (e.g., Calico).
- **Workload hardening:**
  - Non-root user, read-only root filesystem, dropped capabilities.
  - Requests and limits, liveness/readiness/startup probes.
  - PodDisruptionBudget and topology spread across workers.

### 3.3 Local → AWS mapping

| Local (kind) | AWS (EKS) |
|---|---|
| kind + Docker | VPC (2–3 AZs, public/private subnets) + EKS managed node groups |
| Calico | VPC CNI with network policy enabled |
| `local-path` PVC | EBS CSI driver + encrypted `gp3` StorageClass |
| Registry container | ECR (scan on push) |
| NodePort + port mapping | AWS Load Balancer Controller → NLB in front of Envoy |
| Self-signed CA (cert-manager) | ACM, or cert-manager + Let's Encrypt |
| CNPG-generated Secrets | External Secrets Operator + AWS Secrets Manager (EKS Pod Identity) |
| Local Terraform state | S3 backend with native locking, versioning and encryption |
| In-cluster DB (CNPG, 1 instance) | CNPG 3 instances + S3 backups (**RDS documented as the production alternative**) |

---

## 4. Tech stack

| Layer | Choice | Rationale |
|---|---|---|
| Runtime | Docker | kind runs nodes as containers |
| Cluster | **kind**, node image pinned to the **same Kubernetes minor as EKS** | Version parity; 2 workers for spreading and drain demos |
| IaC | **Terraform** providers: `tehcyx/kind`, `kreuzwerker/docker`, `hashicorp/helm`, `hashicorp/kubernetes` | Every resource declared in one tool; pin the community kind provider |
| CNI | **Calico** (default kind CNI disabled) | Reliable NetworkPolicy enforcement, so DB isolation can be proven |
| Registry | `registry:2` container on the kind network | Mimics the ECR push/pull flow; same flow in CI |
| Ingress | **Envoy Gateway** (Gateway API) | Forward-looking standard; same controller on EKS behind an NLB |
| Host exposure | `extraPortMappings` 80/443 → NodePort | Works on macOS, Linux and Windows (`cloud-provider-kind` as a Linux alternative) |
| DNS | `*.localtest.me` | Resolves to 127.0.0.1, so no hosts-file edits |
| TLS | **cert-manager** + self-signed local CA | Same Certificate workflow as cloud |
| Database | **CloudNativePG** operator + official `cluster` chart, PVC | Failover and backups handled by the operator; auto-generated credentials keep secrets out of Terraform state |
| Autoscaling | metrics-server + HPA | metrics-server needs the insecure kubelet TLS flag on kind (local only, documented) |
| API | **FastAPI** + SQLAlchemy + Alembic, `/healthz`, `/readyz`, `/metrics`, JSON logs | Small, fast to build, observable |
| Metrics / alerts | **kube-prometheus-stack** (Prometheus, Alertmanager, Grafana) | De-facto standard; ServiceMonitors |
| Logs | **Loki** (single-binary) + **Grafana Alloy** | Promtail is deprecated in favour of Alloy |
| Grafana | **In-cluster** via Helm, exposed at `grafana.localtest.me` | Parity with EKS, native discovery, dashboards as code. `grafana/otel-lgtm` Docker container only for Phase 3 debugging. |
| Secrets (local) | Operator-generated Kubernetes Secrets | External Secrets + Secrets Manager on AWS |
| GitOps (bonus) | **Argo CD**, bootstrapped by Terraform | Terraform owns the platform; Argo CD owns app delivery |
| CI/CD (bonus) | GitHub Actions; OIDC to AWS (no static keys) | Industry standard |
| Task runner | Taskfile / Makefile | One command per action |

---

## 5. Terraform design

### 5.1 Three stacks per environment (separate state each, applied in order)

| Stack | Contents | Why separate |
|---|---|---|
| `10-cluster` | Registry container, kind cluster (AWS: VPC, EKS, ECR, IAM), kubeconfig output | Helm/Kubernetes providers cannot be reliably configured from a cluster created in the same apply |
| `20-platform` | Calico → cert-manager → Envoy Gateway → metrics-server → CNPG operator → observability → (Argo CD) | Controllers and **CRDs** must exist before resources that use them |
| `30-apps` | `notes` namespace, CNPG `Cluster`, Gateway/HTTPRoute, Notes API Helm release | Fast-changing layer; later handed over to Argo CD |

### 5.2 Rules

- **Modules:** reusable modules live in `infra/modules/`; environment folders contain **wiring and `tfvars` only**.
- **Provider configuration:** never inside modules, only in root stacks.
- **Pinning:** pin Terraform, provider, chart and image versions; never use `latest`.
- **Variables and outputs:** every variable has a description, type and validation where useful; outputs are documented with `terraform-docs`.
- **Resource keys:** `for_each` over `count` for keyed resources.
- **Data passing:** stacks exchange data via outputs and `terraform_remote_state` (or a shared kube context name).
- **State:** local state for `local`; S3 with native locking, versioning and encryption for `dev` and `prod`, created by a `bootstrap` stack.
- **No secrets** in `tfvars` or Helm values, because Terraform state stores release values in plain text.
- **Image builds stay out of Terraform.** The task runner or CI builds and pushes `registry/notes-api:<git-sha>`; Terraform receives the tag as a variable.
- **Tags and labels:** consistent, from a shared `tags` / `labels` variable.

---

## 6. Repository structure

```
.
├── app/                     # Notes API source + Dockerfile + .dockerignore
├── charts/
│   └── notes-api/           # Own Helm chart (values per environment, values.schema.json)
├── infra/
│   ├── modules/
│   │   ├── kind-cluster/
│   │   ├── platform-addons/
│   │   ├── app/
│   │   ├── network/         # AWS
│   │   ├── eks/             # AWS
│   │   ├── ecr/             # AWS
│   │   └── iam/             # AWS
│   ├── bootstrap/           # S3 state bucket (AWS)
│   └── environments/
│       ├── local/{10-cluster,20-platform,30-apps}/
│       ├── dev/{10-cluster,20-platform,30-apps}/
│       └── prod/{10-cluster,20-platform,30-apps}/   # planned, not necessarily applied
├── gitops/                  # Argo CD Applications (bonus)
├── observability/           # Dashboards, alert rules, SLO definitions as code
├── tests/                   # Smoke / e2e scripts
├── docs/
│   ├── user-story.md
│   ├── adr/
│   ├── architecture.md      # Diagrams
│   ├── genai.md             # AI prompts, outputs, validation, corrections
│   └── runbook.md
├── .github/workflows/
├── CLAUDE.md                # AI assistant conventions and rules
├── Taskfile.yml / Makefile
├── .pre-commit-config.yaml
└── README.md
```

---

## 7. Execution plan (ordered phases)

> Each phase has a goal, steps and **Done when** criteria. Do not start a phase until the previous one meets its criteria, except where noted as parallel.

### Phase 0: Prerequisites and environment setup
**Goal:** a working toolchain and safe accounts.
1. Install all tools from §2.2 and verify versions.
2. Allocate Docker resources (≥ 8 GB RAM, ≥ 4 CPUs).
3. Create the AWS billing budget and alert (even if AWS comes later).
4. Confirm the decisions in §2.3 and check current chart and provider versions.

**Done when:** every tool runs, and versions are recorded in the README.

---

### Phase 1: Project foundation
**Goal:** a clean, professional repository skeleton.
1. Create the GitHub repo with branch protection on `main` and trunk-based development with short PRs.
2. Add the folder structure from §6, `.gitignore`, `README` skeleton, `LICENSE`.
3. Configure `pre-commit` with `terraform fmt` / `validate`, `tflint`, `trivy` / `checkov`, `hadolint`, `yamllint`, `helm lint`, `kubeconform`, end-of-file and secret detection.
4. Create the task runner with placeholder targets: `up`, `down`, `build`, `test`, `lint`.
5. Adopt Conventional Commits.

**Done when:** the skeleton is merged and pre-commit runs on an empty repo.

---

### Phase 2: User story, epic and ADRs
**Goal:** the user story drives everything that follows.

1. **Write the epic in `docs/user-story.md`.**
   > *As a platform team, we want to deploy the Notes API with a persistent PostgreSQL database on a reproducible Kubernetes platform, so that product teams can ship features safely across environments without manual infrastructure work.*

2. **Break the epic into stories with acceptance criteria** (one per phase below):

   | Story | Area | Example acceptance criteria |
   |---|---|---|
   | S1 | Containerized API | Image builds, runs non-root, scans clean |
   | S2 | Local cluster as code | `task up` creates the cluster; `task down` removes it |
   | S3 | Platform add-ons | Gateway, TLS, CNI, metrics and DB operator installed by Terraform |
   | S4 | API deployment via Helm | Multiple replicas, probes, HPA, PDB |
   | S5 | Persistent DB, private | Data survives pod deletion; unreachable from outside |
   | S6 | Network isolation | Only the API can reach the DB (proven by test) |
   | S7 | Observability | Dashboards, logs, 3 alerts, 2 SLOs |
   | S8 | CI/CD | PR checks + ephemeral kind e2e |
   | S9 | GitOps | Argo CD syncs the app from Git |
   | S10 | AWS environment as code | dev stacks validated, scanned and cost-estimated |
   | S11 | AI-assisted IaC documented | `docs/genai.md` complete |

3. **Write ADRs:**
   - ADR-001 kind + Terraform for local
   - ADR-002 three-stack Terraform layout
   - ADR-003 Envoy Gateway / Gateway API over ingress-nginx
   - ADR-004 CloudNativePG (in-cluster) vs RDS
   - ADR-005 Calico on kind
   - ADR-006 Observability stack (in-cluster Grafana, Loki, Alloy)
   - ADR-007 Secrets strategy
   - ADR-008 State backend
   - ADR-009 GitOps ownership split

4. **Add the architecture diagram** to `docs/architecture.md`.

**Done when:** the user story, ADRs and diagram are merged.

---

### Phase 3: AI-assisted workflow setup
**Goal:** Claude works inside your guardrails from the first line of IaC. See §8 for details.
1. Write `CLAUDE.md` covering the architecture, stack, conventions, hard rules and definition of done.
2. Configure Claude Code permissions:
   - Allow read and validation commands.
   - Require approval for `apply`, `destroy`, `helm install` and `kubectl` writes.
   - Keep no AWS credentials in the session.
3. Optionally connect a Terraform MCP server for up-to-date provider docs.
4. Create the `docs/genai.md` template (prompt log format).

**Done when:** a dry-run prompt in plan mode respects `CLAUDE.md` conventions.

---

### Phase 4: Application and Dockerfile
**Goal:** a production-like API image proven outside Kubernetes. (Story S1)
1. **Build the minimal FastAPI app:**
   - CRUD on one resource.
   - DB connection from environment variables.
   - `/healthz` and `/readyz` endpoints, Prometheus `/metrics`.
   - Structured JSON logs that include the pod name.
   - Graceful shutdown on SIGTERM.
2. **Handle migrations with Alembic** as a separate command (it becomes a Kubernetes Job or hook later), never at startup across replicas.
3. **Write the Dockerfile using best practices:**
   - Multi-stage build on a slim or distroless base.
   - Non-root user and pinned versions.
   - `.dockerignore` and OCI labels (git SHA).
4. **Smoke test with Docker Compose** (API + Postgres). Optionally add `grafana/otel-lgtm` for quick telemetry checks.
5. **Run `hadolint` and `trivy image`;** fix the findings or document accepted ones.

**Done when:**
- The Compose stack works end to end.
- Data survives a container restart.
- Scans are clean or exceptions are documented.

---

### Phase 5: Stack `local/10-cluster`
**Goal:** a reproducible cluster created only by Terraform. (Story S2)
1. **Module `kind-cluster`:**
   - 1 control plane + 2 workers, with the node image pinned to the EKS minor version.
   - `extraPortMappings` 80/443.
   - Default CNI disabled.
   - containerd mirror config for the local registry.
2. **Registry container** via the Docker provider, connected to the kind network.
3. **Root stack `environments/local/10-cluster`:**
   - Wires the modules together.
   - Outputs the kubeconfig and context name.
4. **Task targets:** `task cluster:up` and `task cluster:down`.

**Done when:**
- `apply` creates the cluster and registry.
- `destroy` removes everything with no leftovers.
- A re-apply shows no changes (idempotent).

> Nodes stay `NotReady` until the CNI is installed in Phase 6. This is expected.

---

### Phase 6: Stack `local/20-platform`
**Goal:** all platform components installed by Terraform via official Helm charts. (Story S3)

Install in this exact order, with explicit `depends_on`:
1. **Calico.** Nodes become `Ready`.
2. **cert-manager** with CRDs, plus a self-signed `ClusterIssuer` / local CA.
3. **Envoy Gateway** with the `Gateway` resource, exposed via NodePort matching the port mappings.
4. **metrics-server** with the kind-only kubelet TLS flag (documented).
5. **CloudNativePG operator.**
6. **Observability:**
   - kube-prometheus-stack, with Grafana exposed at `grafana.localtest.me`.
   - Loki (single binary) and Grafana Alloy.
   - Datasources provisioned as code.
7. **Namespaces and Pod Security labels** for platform components.

**Done when:**
- All releases are healthy and nodes are `Ready`.
- Grafana is reachable through the gateway.
- A re-apply shows no changes.

---

### Phase 7: Helm chart `charts/notes-api`
**Goal:** a production-grade, configurable chart for the API. (Story S4)

1. **Templates:**
   - Deployment with replicas, requests/limits, all three probes, securityContext and topology spread.
   - ClusterIP Service and HTTPRoute (toggleable).
   - ConfigMap and a Secret *reference* (the CNPG-generated secret).
   - HPA, PDB, ServiceAccount and ServiceMonitor.
   - NetworkPolicies (default deny plus explicit allows from §3.2).
   - Migration Job as a pre-install/pre-upgrade hook.
2. **Values:** `values.yaml` + `values-local.yaml` / `values-dev.yaml` / `values-prod.yaml`, plus `values.schema.json`.
3. **Validation:** `helm lint`, `helm template | kubeconform`, `helm-docs`.

**Done when:** the chart lints, renders, validates and is documented.

---

### Phase 8: Stack `local/30-apps`
**Goal:** the application and database deployed by Terraform. (Story S5)
1. Create the `notes` namespace with Pod Security `restricted`.
2. Create the CNPG `Cluster` (official `cluster` chart):
   - 1 instance locally.
   - PVC on `local-path`.
   - Credentials Secret generated by the operator.
3. Build and push the image to `localhost:5001/notes-api:<git-sha>` with `task build`.
4. Deploy the Notes API Helm release with `values-local.yaml` and the image tag variable.
5. Add `task up` (all stacks in order) and `task down` (reverse order).

**Done when:**
- `task up` goes from zero to a running stack in one command.
- `https://api.localtest.me` responds.

---

### Phase 9: Local validation suite (Functionality criterion)
**Goal:** prove every requirement with a scripted test (`task test`), reusable in CI. (Stories S5, S6)

| # | Check | Proof |
|---|---|---|
| 1 | API reachable from outside | `curl` via gateway returns 200 |
| 2 | DB **not** reachable from outside | No external Service type exists; host connection fails |
| 3 | Only the API reaches the DB | Throwaway pod in `notes` fails to connect to 5432 (NetworkPolicy) |
| 4 | Persistence | Write data → delete DB pod → data still present |
| 5 | Multiple replicas | Scale to 3; responses show different pod names |
| 6 | Autoscaling | `k6` load → HPA scales out → scales back in |
| 7 | Basic modification takes effect | Change a value (message/replicas) → apply → rolling update with zero downtime |
| 8 | Rollback | `helm rollback` restores the previous revision |
| 9 | Resilience | Drain a worker → the API stays available (PDB + spread) |
| 10 | Idempotency | Re-running `apply` on every stack shows no changes |

**Done when:** all checks pass from a fresh `task down && task up`.

---

### Phase 10: Observability (SRE practices)
**Goal:** visible, alertable and measurable service health. (Story S7)
1. **Grafana dashboard as code:** request rate, error rate, p95 latency, replicas, DB connections, pod restarts.
2. **Logs** in Loki via Alloy, with a saved query to filter by namespace or pod.
3. **Alert rules:**
   - API down.
   - 5xx rate above threshold.
   - PVC usage above 80%.
   - Optionally, a pod crash loop.
4. **SLOs in `docs/`:** availability (e.g., 99.5%) and p95 latency (e.g., < 300 ms), each with an error-budget explanation.
5. **Runbook** in `docs/runbook.md` covering each alert.

**Done when:** the load test is visible on the dashboard, an induced failure fires an alert, and logs are searchable.

---

### Phase 11: CI/CD with GitHub Actions
**Goal:** every change is automatically validated. (Story S8)
1. **PR workflow:**
   - `terraform fmt` / `validate`, `tflint`, `trivy` / `checkov`.
   - `hadolint`, `helm lint`, `kubeconform`, `yamllint`.
   - Build the image and run `trivy image`.
2. **E2E job:** an ephemeral kind cluster in CI → `task up` → `task test` (Phase 9 suite) → teardown.
3. **Main-branch workflow:**
   - Push the image tagged with the git SHA.
   - Update the image tag in environment values (or the GitOps repo path).
4. **Optional:** Infracost comment on PRs that touch AWS stacks.
5. **For AWS (later):** GitHub OIDC → IAM role. No static credentials.

**Done when:** PRs are blocked on failing checks, and the e2e job passes.

---

### Phase 12: GitOps with Argo CD (bonus)
**Goal:** a clean ownership split, where Terraform owns the platform and Argo CD owns app delivery. (Story S9)
1. Install Argo CD in `20-platform` via Terraform.
2. Create an app-of-apps (or ApplicationSet) in `gitops/` pointing at the Notes API chart and environment values.
3. Migrate the Notes API release from `30-apps` to Argo CD. Keep `30-apps` for the namespace and the DB if desired, and document the boundary.
4. Demo: a merged PR changes a value → Argo CD syncs → a rolling update follows.

**Done when:** an app change reaches the cluster with no manual apply.

---

### Phase 13: AWS environment as code (`dev`, `prod`)
**Goal:** cloud-ready IaC, validated without needing to deploy. This is also the **representative part for the GenAI section**. (Story S10)
1. **`bootstrap`:** S3 state bucket with versioning, encryption and blocked public access.
2. **Modules:**
   - **`network`:** VPC across 2–3 AZs, public/private subnets, a single NAT in dev, VPC flow logs.
   - **`eks`:**
     - Prefer the official `terraform-aws-modules`.
     - Private endpoint, or public access restricted to a CIDR list.
     - KMS secrets encryption and control-plane logging.
     - Access entries (no `aws-auth`).
     - IMDSv2, an on-demand system node group and a Spot app node group.
     - Add-ons: VPC CNI with network policy, CoreDNS, kube-proxy, EBS CSI, Pod Identity agent.
   - **`ecr`:** scan on push, immutable tags, lifecycle policy.
   - **`iam`:** least-privilege roles (AWS Load Balancer Controller, External Secrets, EBS CSI) and a GitHub OIDC role.
3. **Platform differences for AWS:**
   - AWS Load Balancer Controller → NLB in front of Envoy.
   - `gp3` encrypted StorageClass.
   - External Secrets + Secrets Manager.
   - CNPG with 3 instances and S3 backups.
4. **`prod` environment:** same modules, different values (more AZs, NAT per AZ, larger nodes, deletion protection). Planned, not necessarily applied.
5. **Offline validation:**
   - `terraform validate`
   - `tflint` with the AWS ruleset
   - `checkov` / `trivy`
   - `infracost breakdown` (record the monthly estimate for dev and prod)

**Done when:** all AWS stacks validate, scan clean (or have justified suppressions), and have documented cost estimates.

---

### Phase 14: Deploy to AWS (optional bonus)
**Goal:** prove the "local ≈ cloud" claim.
1. Apply `bootstrap` → `dev/10-cluster` → `dev/20-platform` → `dev/30-apps` (or let Argo CD sync).
2. Run the Phase 9 suite against the NLB hostname.
3. Capture evidence: screenshots or a short recording for the presentation.
4. **Destroy immediately after testing.** The EKS control plane, NAT gateway and NLB bill hourly. Script `task aws:down` and verify no orphaned load balancers, EBS volumes or ENIs remain.

**Done when:** the suite passes on EKS and everything is destroyed with no leftovers.

---

### Phase 15: GenAI documentation (continuous, finalized here)
**Goal:** satisfy the exercise's Generative AI section with evidence. (Story S11)

`docs/genai.md` contains:
1. **Tool and setup:** Claude Code, `CLAUDE.md`, guardrails, permissions.
2. **The prompt(s)** used for the representative part (AWS EKS module + Notes API chart).
3. **Output:** meaningful excerpts of the raw AI output.
4. **Validation:** which tools ran and what they flagged (validate, tflint, checkov / trivy, kubeconform, kind deployment).
5. **Corrections:** the before/after diff (separate commits) and why each change was needed.
6. **Edge cases, security and compliance:** CRD ordering, destroy order, secrets in state, IAM scope, exposure.
7. **Performance, cost and idiomatic use:** Infracost results, sizing, official modules, pinning, `for_each`.
8. **Lessons learned:** 2–3 honest "the AI got this wrong" stories.

**Done when:** every bullet in the exercise's GenAI section is answered with evidence.

---

### Phase 16: Presentation and code-review preparation
**Goal:** a clear, confident presentation and a defensible codebase.
1. **Storyline (about 20–30 minutes):**
   1. User story and epic.
   2. Architecture and key ADRs (trade-offs).
   3. Repository tour: Terraform stacks, modules, chart.
   4. Live demo of the Phase 9 checks on kind (or the EKS recording).
   5. Observability: dashboard, logs, alert.
   6. CI/CD and GitOps flow.
   7. The GenAI section.
   8. What I'd do next.
2. **Prepare answers to likely questions:**
   - Why in-cluster DB vs RDS?
   - How do secrets flow?
   - How is state locked?
   - How do you promote dev → prod?
   - What happens when a node dies?
   - How do you upgrade EKS?
   - Why three stacks?
   - Why Gateway API?
3. **Rehearse** against a freshly created environment and time the demo.
4. **Final repo polish:** README quick start, all docs linked, no TODOs, clean history.
5. **Share the repository** by the requested deadline.

**Done when:** you have done a full rehearsal from scratch with no manual steps, and you can explain every line of code.

---

## 8. AI-assisted IaC workflow (Claude)

### 8.1 Principles
- You are the architect; Claude is the pair-programmer working inside your guardrails.
- Use **Claude Code inside the repo** so it can read the ADRs and run the validation tools itself.
- Never ask for "the whole infrastructure". Work in **thin vertical slices** matching the phases.

### 8.2 `CLAUDE.md` contents
- **Architecture:** the three stacks and module boundaries; environment folders contain wiring only.
- **Stack:** kind, Calico, Envoy Gateway, CloudNativePG, Prometheus/Grafana/Loki/Alloy.
- **Conventions:**
  - Naming, tags and labels.
  - Pinned versions, no `latest`.
  - `versions.tf` / `variables.tf` / `outputs.tf` in every module.
  - Variable descriptions and validations.
  - No provider config in modules.
- **Hard rules:**
  - No secrets in code, `tfvars` or Helm values.
  - Nothing public except the gateway.
  - Least-privilege IAM.
  - Pod Security `restricted`.
- **Definition of done:** fmt, validate, tflint, trivy / checkov, helm lint and kubeconform all pass.

### 8.3 The loop for each slice
1. **Plan mode.** Claude proposes files, resources, variables and open questions; you review and correct.
2. **Generate one module or chart** against the approved plan.
3. **Claude runs the full verification suite** and fixes what fails.
4. **You review the diff** with the checklist in §8.5.
5. **Apply to kind and run that slice's tests.**
6. **Commit the raw AI output, then commit your corrections separately,** and log the prompt in `docs/genai.md`.

### 8.4 Prompt anatomy

| Part | Content |
|---|---|
| Role and goal | Senior platform engineer; create module X for environment Y |
| Context pointers | Follow `CLAUDE.md` and the relevant ADRs; who consumes the module |
| Functional requirements | Resources, inputs, outputs |
| Non-functional constraints | Security, cost, pinning, naming, tags |
| Explicit exclusions | e.g., no wildcard IAM, no hardcoded region or account, no `aws-auth` |
| Verification and output | Run the tools, fix or justify findings, generate docs, **list assumptions and uncertainties** |

### 8.5 Review checklist for AI-generated IaC
- **Validation:**
  - Do the arguments exist in the *pinned* provider or chart version? Hallucinated or deprecated arguments are the most common error.
  - Does the plan or rendered output match expectations?
- **Common corrections:**
  - Broad IAM, missing securityContext, probes or limits.
  - Hardcoded values, `latest` tags.
  - Provider config inside modules, cross-stack cycles.
- **Edge cases:**
  - CRD ordering and destroy order (orphaned PVCs and load balancers).
  - Idempotency on re-apply.
  - Node loss with `local-path` volumes.
- **Security and compliance:**
  - Secrets in state or values.
  - Unintended exposure.
  - Encryption at rest.
  - NetworkPolicies actually tested.
- **Cost and performance:**
  - Infracost, NAT and load-balancer count.
  - Node sizing versus pod requests.
  - HPA thresholds.
- **Idiomatic use:**
  - Official modules, `for_each`, small composable modules.
  - `values.schema.json`.

### 8.6 Do not delegate
Architecture and ADRs, security boundaries, final review of every diff, and the `apply` decision. Commit nothing you cannot explain line by line.

---

## 9. Definition of Done (global)

A change is done only when all of the following hold:
- [ ] `terraform fmt` / `validate`, `tflint`, `trivy` / `checkov` pass (or suppressions are justified inline)
- [ ] `helm lint`, `kubeconform`, `hadolint`, `yamllint` pass
- [ ] Docs regenerated (`terraform-docs`, `helm-docs`)
- [ ] Deployed to kind and the relevant `task test` checks pass
- [ ] Re-apply shows no changes
- [ ] No secrets, no `latest` tags, versions pinned
- [ ] The related story's acceptance criteria are met
- [ ] Prompt log updated if AI was used

---

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Laptop runs out of memory with observability | Allocate ≥ 8 GB to Docker; reduce Prometheus retention and replicas locally |
| Helm/Kubernetes providers fail with a cluster created in the same apply | Three-stack design with separate state |
| CRDs missing at plan time | CRDs installed in `20-platform`; CRs only in `30-apps` |
| Deprecated or retired components | Verify status before pinning (ingress-nginx, Bitnami, Promtail) |
| AI hallucinates arguments or outdated versions | Pinned versions, Terraform MCP / official docs, automated validation |
| Secrets leak into Terraform state | Operator-generated secrets locally; External Secrets on AWS |
| AWS cost overrun | Billing alert, single NAT and Spot in dev, scripted destroy, Infracost |
| Orphaned AWS resources after destroy | Correct destroy order (apps → platform → cluster); post-destroy check for load balancers, EBS volumes and ENIs |
| Demo fails live | Rehearse from scratch; keep a recording as backup |
| Running out of time | Core path first (Phases 0–9); bonuses in priority order 10 → 11 → 13 → 12 → 14 |

---

## 11. Milestone checklist

**Milestone 1: Core requirements (local)**
- [ ] Phase 0 Prerequisites
- [ ] Phase 1 Repository foundation
- [ ] Phase 2 User story, epic, ADRs
- [ ] Phase 3 AI workflow setup
- [ ] Phase 4 API + Dockerfile
- [ ] Phase 5 `10-cluster`
- [ ] Phase 6 `20-platform`
- [ ] Phase 7 Helm chart
- [ ] Phase 8 `30-apps`
- [ ] Phase 9 Validation suite passing

**Milestone 2: High-value bonuses (no AWS cost)**
- [ ] Phase 10 Observability
- [ ] Phase 11 CI/CD
- [ ] Phase 13 AWS IaC validated offline
- [ ] Phase 12 GitOps

**Milestone 3: Cloud and delivery**
- [ ] Phase 14 AWS deployment (optional)
- [ ] Phase 15 GenAI documentation finalized
- [ ] Phase 16 Presentation rehearsed and repository shared

> **Priority guidance:** a polished, fully reproducible local stack with CI, observability and a strong review story is worth more than a half-working EKS deployment. AWS deployment is a bonus; AWS IaC that is validated, scanned and cost-estimated is the expected professional standard.
