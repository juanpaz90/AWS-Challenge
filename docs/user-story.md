# User Story and Epic

> The user story drives the work. Every phase in [`project-plan.md`](project-plan.md) maps to one story below, and a story is closed only when all of its acceptance criteria are proven by a scripted test or recorded evidence.

## Epic

> **As a** platform team,
> **we want** to deploy the Notes API with a persistent PostgreSQL database on a reproducible Kubernetes platform,
> **so that** product teams can ship features safely across environments without manual infrastructure work.

### Epic-level acceptance criteria

- The API runs with multiple replicas and is reachable from outside the cluster.
- The database uses persistent storage and is **not** reachable from outside the cluster.
- Every resource is created by Terraform, Helm or GitOps. No manual `kubectl apply`, console clicks or `eksctl create`.
- The same charts and platform layer run on `kind` (local) and AWS EKS (cloud); only the cluster layer changes.
- One command each brings an environment up (`task up`), tests it (`task test`) and tears it down (`task down`).

### Out of scope

- Multi-region deployment.
- Production traffic, real users or real data.
- A managed database in the local environment (RDS is documented as the production alternative in [ADR-004](adr/0004-cloudnativepg-vs-rds.md)).

---

## Stories

| ID | Story | Phase | Priority |
|---|---|---|---|
| [S1](#s1--containerized-api) | Containerized API | 4 | Core |
| [S2](#s2--local-cluster-as-code) | Local cluster as code | 5 | Core |
| [S3](#s3--platform-add-ons) | Platform add-ons | 6 | Core |
| [S4](#s4--api-deployment-via-helm) | API deployment via Helm | 7 | Core |
| [S5](#s5--persistent-private-database) | Persistent, private database | 8, 9 | Core |
| [S6](#s6--network-isolation) | Network isolation | 9 | Core |
| [S7](#s7--observability) | Observability | 10 | Bonus (1) |
| [S8](#s8--cicd) | CI/CD | 11 | Bonus (2) |
| [S9](#s9--gitops) | GitOps | 12 | Bonus (4) |
| [S10](#s10--aws-environment-as-code) | AWS environment as code | 13 | Bonus (3) |
| [S11](#s11--ai-assisted-iac-documented) | AI-assisted IaC documented | 15 | Required |

Bonus priority follows the plan: Observability → CI/CD → AWS IaC → GitOps → AWS deployment.

---

### S1 — Containerized API

**As a** developer, **I want** the Notes API packaged as a hardened container image, **so that** it runs the same way on a laptop, in CI and on Kubernetes.

**Acceptance criteria** — ✅ met in Phase 4 (`task app:test`, `task scan`, `task compose:smoke`)

- [x] **Given** the source in `app/`, **when** I run `task build`, **then** an image `notes-api:<git-sha>` is built from a multi-stage Dockerfile with pinned base image versions.
- [x] The container runs as a non-root user and works with a read-only root filesystem.
- [x] The API exposes CRUD for notes, plus `/healthz`, `/readyz` and `/metrics`.
- [x] Logs are structured JSON and include the pod/host name.
- [x] The process shuts down gracefully on `SIGTERM` (in-flight requests complete).
- [x] Database migrations run as a separate Alembic command, never at application startup.
- [x] `hadolint` passes and `trivy image` reports no HIGH/CRITICAL findings, or each accepted finding is documented.
- [x] Docker Compose (API + Postgres) works end to end, and data survives a container restart.

---

### S2 — Local cluster as code

**As a** platform engineer, **I want** the local Kubernetes cluster and image registry created only by Terraform, **so that** anyone can reproduce the environment with one command.

**Acceptance criteria**

- [ ] `task cluster:up` creates a kind cluster (1 control plane + 2 workers) and a local registry at `localhost:5001`.
- [ ] The kind node image is pinned to the same Kubernetes minor version as the target EKS version.
- [ ] Host ports 80 and 443 are mapped to the cluster; the default CNI is disabled.
- [ ] kind nodes can pull images from the local registry.
- [ ] A second `terraform apply` shows **no changes**.
- [ ] `task cluster:down` removes the cluster and registry with no leftover containers, networks or volumes.

---

### S3 — Platform add-ons

**As a** platform engineer, **I want** networking, TLS, ingress, metrics and the database operator installed by Terraform from official Helm charts, **so that** applications have a consistent platform to run on.

**Acceptance criteria**

- [ ] Calico, cert-manager, Envoy Gateway, metrics-server and the CloudNativePG operator are installed in order with explicit dependencies.
- [ ] All nodes are `Ready` after Calico is installed.
- [ ] A self-signed `ClusterIssuer` issues certificates for `*.localtest.me`.
- [ ] A shared `Gateway` listens on 80/443 and is reachable from the host.
- [ ] Every platform namespace has Pod Security Admission labels; any exception is documented.
- [ ] Every chart version is pinned and its project status (active, deprecated, retired) was verified before pinning.
- [ ] A re-apply shows no changes.

---

### S4 — API deployment via Helm

**As a** developer, **I want** a production-grade Helm chart for the Notes API, **so that** I can deploy it to any environment by changing values only.

**Acceptance criteria**

- [ ] The Deployment runs ≥ 2 replicas with requests/limits, liveness/readiness/startup probes and topology spread across nodes.
- [ ] Pods satisfy Pod Security `restricted` (non-root, read-only root FS, all capabilities dropped, `seccompProfile: RuntimeDefault`).
- [ ] The chart includes a ClusterIP Service, an optional HTTPRoute, HPA, PDB, ServiceAccount, ServiceMonitor and NetworkPolicies.
- [ ] Database credentials come from a **reference** to the operator-generated Secret; no secret values appear in values files.
- [ ] Migrations run as a `pre-install`/`pre-upgrade` hook Job.
- [ ] `values.schema.json` validates all values; per-environment files exist (`values-local.yaml`, `values-dev.yaml`, `values-prod.yaml`).
- [ ] `helm lint`, `helm template | kubeconform` and `helm-docs` all pass.

---

### S5 — Persistent, private database

**As a** product team, **I want** the Notes data stored in PostgreSQL on persistent storage that only the API can reach, **so that** data is durable and not exposed.

**Acceptance criteria**

- [ ] A CloudNativePG `Cluster` runs in the `notes` namespace with its data on a PVC.
- [ ] Credentials are generated by the operator and never stored in Terraform state, `tfvars` or Helm values.
- [ ] **Persistence:** write a note → delete the DB pod → the note is still returned after the pod restarts.
- [ ] **Not public:** no Service of type `NodePort` or `LoadBalancer`, and no route, points at the database; a connection attempt from the host fails.
- [ ] `task up` goes from zero to a working stack in one command, and `https://api.localtest.me` responds.

---

### S6 — Network isolation

**As a** security reviewer, **I want** default-deny networking with explicit allows, **so that** only the API can reach the database.

**Acceptance criteria**

- [ ] The `notes` namespace has a default-deny NetworkPolicy for ingress and egress.
- [ ] Explicit allows exist only for: gateway → API, API → DB (5432), CNPG operator → DB, monitoring → metrics ports, and DNS egress to `kube-system`.
- [ ] **Proven by test:** a throwaway pod in `notes` without the API labels **cannot** connect to the DB on 5432.
- [ ] **Proven by test:** the API **can** connect to the DB.

---

### S7 — Observability

**As an** SRE, **I want** metrics, logs, dashboards, alerts and SLOs defined as code, **so that** service health is visible and measurable.

**Acceptance criteria**

- [ ] A Grafana dashboard (as code) shows request rate, error rate, p95 latency, replica count, DB connections and pod restarts.
- [ ] API logs are searchable in Loki by namespace and pod.
- [ ] Alerts exist for: API down, 5xx rate above threshold, PVC usage > 80% (optional: crash loop).
- [ ] SLOs for availability and p95 latency are documented with error budgets in [`slo.md`](slo.md).
- [ ] Each alert has a runbook entry in [`runbook.md`](runbook.md).
- [ ] A `k6` load test is visible on the dashboard, and an induced failure fires an alert.

---

### S8 — CI/CD

**As a** team, **we want** every change validated automatically, **so that** broken infrastructure or images never reach `main`.

**Acceptance criteria**

- [ ] PR checks run `terraform fmt`/`validate`, `tflint`, `trivy`/`checkov`, `hadolint`, `helm lint`, `kubeconform` and `yamllint`.
- [ ] The image is built and scanned with `trivy image` on every PR.
- [ ] An e2e job creates an ephemeral kind cluster, runs `task up` and `task test`, then tears down.
- [ ] `main` is protected; PRs cannot merge with failing checks.
- [ ] Merges to `main` publish the image tagged with the git SHA.
- [ ] AWS access from CI uses GitHub OIDC; no static credentials exist anywhere.

---

### S9 — GitOps

**As a** platform team, **we want** Argo CD to deliver the application from Git, **so that** app changes reach the cluster without a manual apply.

**Acceptance criteria**

- [ ] Argo CD is installed by Terraform in `20-platform`.
- [ ] An app-of-apps (or ApplicationSet) in `gitops/` deploys the Notes API chart with environment values.
- [ ] The ownership boundary between Terraform and Argo CD is documented in [ADR-009](adr/0009-gitops-ownership-split.md).
- [ ] **Demo:** a merged PR changes a value → Argo CD syncs → a rolling update completes with zero downtime.

---

### S10 — AWS environment as code

**As a** platform team, **we want** the AWS `dev` and `prod` environments defined with the same modules and charts, **so that** we can move to the cloud without redesign.

**Acceptance criteria**

- [ ] A `bootstrap` stack creates the S3 state bucket (versioning, encryption, public access blocked, native locking).
- [ ] Modules exist for `network`, `eks`, `ecr` and `iam`, and `dev`/`prod` folders contain wiring and `tfvars` only.
- [ ] `terraform validate`, `tflint` (AWS ruleset) and `checkov`/`trivy` pass, or suppressions are justified inline.
- [ ] `infracost breakdown` monthly estimates for `dev` and `prod` are recorded.
- [ ] *(Optional, Phase 14)* The Phase 9 test suite passes against EKS, and `task aws:down` leaves no orphaned load balancers, EBS volumes or ENIs.

---

### S11 — AI-assisted IaC documented

**As a** reviewer, **I want** to see how AI was used to produce infrastructure code and how its output was validated, **so that** I can judge the quality and safety of the process.

**Acceptance criteria**

- [ ] [`genai.md`](genai.md) documents the tool, setup, guardrails and permissions.
- [ ] It includes the prompts, excerpts of raw output, validation results and before/after corrections.
- [ ] Raw AI output and human corrections are in **separate commits**, linked from the log.
- [ ] It covers edge cases, security/compliance, cost/performance and idiomatic use.
- [ ] It includes at least 2–3 honest "the AI got this wrong" lessons.

---

## Phase 9 validation matrix

Traceability between the scripted checks (`task test`) and the stories above.

| # | Check | Proof | Story |
|---|---|---|---|
| 1 | API reachable from outside | `curl` via gateway returns 200 | S5 |
| 2 | DB not reachable from outside | No external Service type exists; host connection fails | S5 |
| 3 | Only the API reaches the DB | Throwaway pod in `notes` fails to connect to 5432 | S6 |
| 4 | Persistence | Write → delete DB pod → data still present | S5 |
| 5 | Multiple replicas | Scale to 3; responses show different pod names | S4 |
| 6 | Autoscaling | `k6` load → HPA scales out → scales back in | S4 |
| 7 | Basic modification takes effect | Change a value → apply → zero-downtime rolling update | S4 |
| 8 | Rollback | `helm rollback` restores the previous revision | S4 |
| 9 | Resilience | Drain a worker → API stays available | S4 |
| 10 | Idempotency | Re-apply on every stack shows no changes | S2, S3 |
