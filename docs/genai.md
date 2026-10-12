# Generative AI in this project

> Evidence for the exercise's Generative AI section. Updated continuously and finalised in Phase 15. Story: S11.
> Principle: **I am the architect; Claude is the pair-programmer working inside my guardrails.** Architecture, ADRs, security boundaries, final review and the `apply` decision are not delegated.

## 1. Tool and setup

| Item | Value |
|---|---|
| Assistant | Claude Code (CLI), model: Claude Opus 5.5 (`claude-opus-5-5`) |
| Project rules | [`CLAUDE.md`](../CLAUDE.md) — architecture, conventions, hard rules, guardrails, definition of done |
| Context sources | ADRs in [`adr/`](adr/README.md), [`architecture.md`](architecture.md), [`project-plan.md`](project-plan.md), [`user-story.md`](user-story.md) |
| Up-to-date docs | Terraform MCP server `hashicorp/terraform-mcp-server:1.3.0` (Docker, stdio), configured in [`.mcp.json`](../.mcp.json); provider/module docs are read for the **pinned** version instead of relying on model memory |
| Permissions | [`.claude/settings.json`](../.claude/settings.json), committed so the guardrails are reviewable. **Allowed:** read-only and validation commands (`terraform fmt/validate/init/plan`, `tflint`, `trivy`, `checkov`, `hadolint`, `yamllint`, `kubeconform`, `helm lint/template/show`, `kubectl get/describe/logs/diff`). **Ask every time:** `terraform apply/destroy/import/state rm`, `helm install/upgrade/uninstall/rollback`, every `kubectl` write, `kind create/delete`, `task up/down/build`, `git push`. **Denied:** reading `~/.aws`, `~/.kube/config`, `.env`, `*.tfstate`; `aws configure/sso/sts`; `eksctl create/delete`. |
| Credentials | No AWS credentials in the Claude session: the settings `env` block points `AWS_CONFIG_FILE` / `AWS_SHARED_CREDENTIALS_FILE` at `/dev/null` and blanks `AWS_PROFILE` and the key variables, so Terraform and the AWS CLI find no credentials. AWS stacks are validated offline; AWS applies are run by a human outside the session. |
| Commit hooks | [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) runs the same validators on every commit, so AI output is checked even when nobody asks for it |

### Guardrail design notes

- Permission rules match command prefixes, so flag-first forms (`terraform -chdir=… apply`, `kubectl -n notes delete …`) have their own `ask` patterns. Ask/deny rules take precedence over allow rules, so any ambiguous match falls to the safer side.
- The guardrails reduce risk; they are not a sandbox. A command could still reach credentials by an unusual path, so the final review and the `apply` decision stay with the human ([plan §8.6](project-plan.md#86-do-not-delegate)).

### Workflow per slice

1. **Plan mode** — Claude proposes files, resources, variables and open questions; I review and correct.
2. **Generate** one module or chart against the approved plan.
3. **Verify** — Claude runs the full validation suite and fixes what fails.
4. **Review** — I review the diff with the checklist in [§8.5 of the plan](project-plan.md#85-review-checklist-for-ai-generated-iac).
5. **Apply** to kind and run the slice's tests.
6. **Commit** raw AI output, then my corrections in a **separate commit**, and log the entry below.

---

## 2. Representative part

The representative AI-assisted parts are:

- **A.** AWS EKS module (`infra/modules/eks`) — Phase 13
- **B.** Notes API Helm chart (`charts/notes-api`) — Phase 7

For each, sections 3–8 below are filled in.

---

## 3. Prompt log

Copy this block for every significant AI interaction.

```markdown
### P-NNN — <short title>

- **Date:** YYYY-MM-DD
- **Phase / story:** Phase N / SN
- **Goal:** what this slice must produce
- **Mode:** plan → generate → verify

**Prompt**

> Role and goal: …
> Context pointers: follow CLAUDE.md and ADR-000X; consumers of this module are …
> Functional requirements: resources, inputs, outputs …
> Non-functional constraints: security, cost, pinning, naming, tags …
> Explicit exclusions: no wildcard IAM, no hardcoded region/account, no aws-auth …
> Verification and output: run fmt/validate/tflint/checkov, fix or justify findings, generate docs, list assumptions and uncertainties.

**Raw output (excerpt)**

    <the meaningful part of what Claude produced>

**Commits**

- Raw AI output: `<sha>`
- Human corrections: `<sha>`

**Validation results**

| Tool | Result | Findings |
|---|---|---|
| terraform validate | | |
| tflint | | |
| checkov / trivy | | |
| helm lint / kubeconform | | |
| Deployed to kind / plan | | |

**Corrections and why**

| # | What the AI produced | What I changed | Why |
|---|---|---|---|
| 1 | | | |

**Assumptions / uncertainties Claude listed**

- …
```

### Entries

### P-001 — Notes API, Dockerfile and Compose smoke test (Phase 4)

- **Date:** 2026-10-11
- **Phase / story:** Phase 4 / S1
- **Goal:** FastAPI CRUD app with probes, metrics, JSON logs, graceful shutdown; Alembic as a separate step; hardened multi-stage image; Compose smoke test; clean scans.
- **Mode:** generate → verify (Claude ran the tests, linters, image scan and smoke test itself)

**Prompt**

> Following docs/project-plan.md, let's go with Phase 4: Application and Dockerfile.

The short prompt worked because `CLAUDE.md`, the plan and the ADRs supplied the constraints (pinning, non-root, no secrets, migrations not at startup).

**Commits**

- Raw AI output: _fill in_
- Human corrections: _fill in_

**Validation results**

| Tool | Result | Findings |
|---|---|---|
| pytest (12 tests incl. Alembic upgrade/downgrade) | ✅ | 1 failure on first run (see correction 1) |
| ruff check / format | ✅ | 3 files reformatted |
| hadolint | ✅ | none |
| trivy image (HIGH/CRITICAL, fixable) | ✅ after fix | 4 HIGH on first scan (see correction 2) |
| Compose smoke test (9 checks) | ✅ after fixes | 1 false failure, 1 false pass (see corrections 3–4) |

**Corrections and why** (found by the verification loop, before human review)

| # | What the AI produced | What changed | Why |
|---|---|---|---|
| 1 | Metrics middleware resolved the route template **before** calling the app, by re-matching routes | Read `scope["route"]` **after** routing | With Starlette 1.7 the pre-match never matched, so every request was labelled `handler="unmatched"`. A unit test asserting route-template labels caught it. Without that test, the SLO queries would have silently aggregated everything into one series. |
| 2 | Runtime image kept the base image's `pip` | `pip uninstall` in the runtime stage | Trivy found 4 fixable HIGH CVEs in pip's vendored `urllib3`/`msgpack`/`setuptools`. The app never uses pip at runtime. |
| 3 | Smoke check "DB not published" used `docker compose port db 5432` | Inspect the container's real port bindings | `compose port` exits 0 even when nothing is published, so the check failed although the DB was correctly private. |
| 4 | Smoke test ran `compose down/up` without the image tag | Pass `IMAGE_TAG` through and use `up --no-build` | Compose silently **built a second image tagged `dev`** and the test passed against it. A test that can swap the artifact under test is worse than no test. Caught because the reported `version` changed. |
| 5 | Image tag "dirty" detection used `git diff` | Use `git status --porcelain` | `git diff` ignores untracked files, so a build from uncommitted code was tagged as a clean SHA. |
| 6 | Dev dependency `httpx` | `httpx2` | Starlette's TestClient now emits a deprecation warning for `httpx`. |

**Assumptions / uncertainties**

- Python 3.14.8 chosen over 3.15 because 3.15 images were still release candidates.
- One uvicorn worker per container (Prometheus client is not multiprocess-aware here); scaling is by replicas.
- 44 unfixed HIGH Debian findings accepted for now (see `app/README.md`).


---

### P-002 — `kind-cluster` module and `local/10-cluster` stack (Phase 5)

- **Date:** 2026-10-11
- **Phase / story:** Phase 5 / S2
- **Goal:** kind cluster (1 control plane + 2 workers, Kubernetes = EKS minor, default CNI off, 80/443 mappings) and a local registry with a containerd mirror, created and destroyed only by Terraform.
- **Mode:** research → generate → validate offline → plan → apply → test → destroy → test → re-apply

**Prompt**

> Now lets go with Phase 5: Stack local/10-cluster

**Commits**

- Raw AI output: _fill in_
- Human corrections: _fill in_

**Verified against the pinned versions before writing code** (these would otherwise have been plausible-looking mistakes)

| Question | Finding | Effect on the code |
|---|---|---|
| Which node image? | `tehcyx/kind 0.11.0` embeds **kind v0.31.0**; the installed kind CLI is v0.33.0 | Node image taken from the v0.31.0 release notes (`v1.35.0@sha256:452d…`), not the latest kind release |
| Which Kubernetes minor? | EKS 1.37/1.36/1.35 in standard support; kind v0.31.0 ships up to 1.35 | 1.35 for both kind and EKS |
| Where does the provider write kubeconfig? | Unset `kubeconfig_path` → a `<name>-config` credentials file in the stack's working directory | Path set explicitly to `~/.kube/config`; provider removes the context on destroy |
| `wait_for_ready` default? | `false` | Kept `false` explicitly: with the CNI disabled nodes never become Ready |
| docker provider 4.x schema | `labels` are `label`/`value` blocks; provider ignores Docker CLI contexts | Dynamic `labels` blocks; `DOCKER_HOST` resolved from the active context by the task |
| kind's registry guide | Uses `docker exec` to write `hosts.toml` into each node | Replaced by a Terraform-rendered `hosts.toml` mounted via `extraMounts` (declarative) |
| Who deletes the `kind` network? | kind never deletes it | Network created by Terraform, so `destroy` removes it |

**Validation results**

| Tool | Result | Findings |
|---|---|---|
| terraform fmt / validate | ✅ | `fmt` re-aligned one block |
| tflint (recommended preset) | ✅ | none |
| trivy config | ✅ | none |
| terraform-docs (pre-commit) | ✅ | table formatting normalised on first run |
| plan | ✅ | 5 to add, as expected |
| apply + `cluster:check` (6 checks) | ✅ | incl. a real image pull through the mirror |
| re-plan (`-detailed-exitcode`) | ✅ | exit 0, no changes |
| destroy + `cluster:check-clean` | ✅ after fix | see correction 1 |

**Corrections and why**

| # | What the AI produced | What changed | Why |
|---|---|---|---|
| 1 | `cluster:down` = `terraform destroy` only | Also removes `.generated/`; the leftover check covers it | `local_file` deletes the file but not the directories it created, so empty folders survived the destroy. Caught because the leftover check listed the directory. |
| 2 | Lock file with darwin_arm64 hashes only | `terraform providers lock` for linux_amd64 / darwin_amd64 / darwin_arm64 | CI (Phase 11) runs on linux_amd64 and would fail `init` with a checksum mismatch. |

**Assumptions / uncertainties**

- Colima mounts `$HOME` into its VM by default; `generated_dir` must be under it. A different Docker setup may need another path.
- The `local-registry-hosting` ConfigMap from kind's guide is a Kubernetes resource, so it belongs in `20-platform` (Phase 6), not here.
- The custom `kind` network is a plain bridge (no IPv6), which is enough for an IPv4-only cluster.

---

### P-003 — `platform-addons` module and `local/20-platform` stack (Phase 6)

- **Date:** 2026-10-11
- **Phase / story:** Phase 6 / S3
- **Goal:** Calico, cert-manager (+ local CA), Envoy Gateway (+ Gateway via NodePort), metrics-server, CloudNativePG, kube-prometheus-stack, Loki, Alloy — all from Terraform, in order, with Grafana reachable through the gateway.
- **Mode:** research → generate → validate offline → plan → apply (**failed twice**) → fix → apply → test → re-plan

**Prompt**

> lets og with Phase 6: Stack local/20-platform

**Commits**

- Raw AI output: _fill in_
- Human corrections: _fill in_

**Verified against the pinned versions before writing code**

| Question | Finding | Effect on the code |
|---|---|---|
| Chart status | All 8 charts current, none deprecated; Grafana chart now lives in `grafana-community` (pulled in by kube-prometheus-stack) | Versions pinned in `terraform.tfvars` |
| CRs vs CRDs in one stack | `kubernetes_manifest` validates at plan time, before the CRDs exist | Issuers, `EnvoyProxy`, `GatewayClass`, `Gateway`, routes in a local `platform-config` chart; content hash passed as a value so template edits trigger upgrades |
| Envoy Service on kind | Default `externalTrafficPolicy: Local` only answers on nodes with an Envoy pod; kind maps host ports to the control-plane node | `EnvoyProxy` sets `NodePort` + `Cluster` and patches nodePorts 30080/30443 (fields verified in the v1.9.2 CRD schema) |
| Grafana password | Chart generates it and reuses it via `lookup` | No password in values or state; re-plan stays clean |
| Loki default mode | `SimpleScalable` | `deploymentMode: SingleBinary`, scalable targets/caches/gateway disabled |
| Helm provider 3.x | `kubernetes = { ... }` attribute, `set = [...]` list | Provider config written in 3.x syntax |

**Validation results**

| Tool | Result | Findings |
|---|---|---|
| terraform validate / tflint / trivy | ✅ | none |
| helm lint + kubeconform (CRD schemas) on `platform-config` | ✅ | 10/10 valid |
| apply #1 | ❌ | Calico `Installation` CRD missing (correction 1) |
| apply #2 | ❌ | Helm release Secret > 1 MiB (correction 2) |
| apply #3 + `platform:check` (11 checks) | ✅ | nodes Ready, TLS verified against the local CA, Grafana 200, logs in Loki |
| re-plan (`-detailed-exitcode`) | ✅ | exit 0, no changes |
| pre-commit | ✅ after fix | correction 3 |

**Corrections and why**

| # | What the AI produced | What changed | Why |
|---|---|---|---|
| 1 | Single `tigera-operator` release with an `installation` block | Separate CRD install first, `manageCRDs=false` | Since v3.33 the chart ships **no CRDs** (the operator creates them at runtime), so Helm could not apply the `Installation` it renders. The model assumed the long-standing chart layout; the pinned chart had changed. |
| 2 | CRDs as a second `helm_release` (`crd.projectcalico.org.v1`) | `helm_template` data source + one `kubernetes_manifest` per CRD (32) | The rendered CRDs exceed the **1 MiB limit** of the Secret Helm stores each release in, which is exactly why Calico documents `helm template \| kubectl apply --server-side`. Also chose the `v1` CRD chart over `v3`, whose `MutatingAdmissionPolicy` objects Kubernetes 1.35 does not serve by default. |
| 3 | YAML linters excluded Helm templates only under `charts/` | Exclusion widened to module charts | Go templates are not valid YAML until rendered. |

Both failed applies stopped before creating anything (only the namespaces existed), which was confirmed before retrying.

**Assumptions / uncertainties**

- The Helm provider does not surface Kubernetes admission warnings, so "no PSA warnings" is not proven by the apply output; enforcement is proven by the namespaces' labels and pods running.
- `20-platform` destroy has not been exercised separately yet; Phase 9 runs the full `task down && task up`.
- kube-prometheus-stack CRDs are installed from the chart's `crds/` directory, which Helm never upgrades; a chart bump may need a CRD upgrade step.

---

### P-004 — `charts/notes-api` Helm chart (Phase 7)

- **Date:** 2026-10-11
- **Phase / story:** Phase 7 / S4
- **Goal:** production-grade chart: Deployment (probes, security, spread), ClusterIP Service, HTTPRoute, ConfigMap + Secret *reference*, HPA, PDB, ServiceAccount, ServiceMonitor, NetworkPolicies, Alembic hook; per-environment values and a schema.
- **Mode:** research (live cluster + upstream source) → generate → lint/kubeconform → behavioural tests → server-side dry run

**Prompt**

> lets og with Phase 7: Helm chart charts/notes-api

**Commits**

- Raw AI output: _fill in_
- Human corrections: _fill in_

**Verified before writing code**

| Question | Source | Finding |
|---|---|---|
| Envoy proxy / Prometheus / CoreDNS pod labels for NetworkPolicies | running platform | `app.kubernetes.io/name=envoy` + `component=proxy`; `app.kubernetes.io/name=prometheus`; `k8s-app=kube-dns` |
| CNPG `<cluster>-app` Secret keys | operator source v1.30.1 (docs only list contents) | `username`, `password`, `dbname`, `host`, `port` |
| Native `preStop.sleep`, `nodeTaintsPolicy` | `kubectl explain` on 1.35 | both served, so no shell `sleep` in the image is needed |

**Validation results**

| Tool | Result | Findings |
|---|---|---|
| helm lint --strict (local/dev/prod) | ✅ | — |
| kubeconform -strict, K8s 1.35 + CRD schemas | ✅ | 13/13 valid per environment |
| behavioural tests (`tests/chart`, 25) | ✅ | incl. 11 unsafe value sets that must be rejected |
| server-side dry run in a PSA `restricted` namespace | ✅ | 13/13 admitted, no PodSecurity warnings |
| trivy config | ✅ (gate HIGH/CRITICAL) | 2 MEDIUM accepted: KSV-01010 false positive, KSV-0125 local registry |
| helm-docs | ✅ | README generated from `values.yaml` |

**Corrections and why** (design issues found while generating, before any tool flagged them)

| # | First approach | What changed | Why |
|---|---|---|---|
| 1 | Chart creates "allow API → DB" ingress on the database pods | Moved to the database owner (`30-apps`) | The migration Job is a `pre-install` hook, so it runs before any chart resource exists. If the DB's own policies isolated it first, the very first migration would be blocked. |
| 2 | Migration Job with `envFrom` the chart ConfigMap and the chart ServiceAccount | Inline env, default SA, no token | Neither exists yet when a pre-install hook runs; the first install would fail. A test now guards this. |
| 3 | `helm lint` on `values.yaml` alone | Lint/render every overlay with `ci/validate-values.yaml` placeholders | The schema deliberately has **no defaults** for image repository/tag and the DB Secret, so the bare defaults (correctly) fail. |
| 4 | Topology spread on hostname only | `nodeTaintsPolicy: Honor` + `ScheduleAnyway` | Without it the tainted control-plane node counts as a domain, and a hard constraint could block scheduling during the drain test. |

**Assumptions / uncertainties**

- Not deployed yet: replicas, HPA scaling, rollout without downtime and drain behaviour are proven in Phases 8–9.
- The ServiceMonitor's Prometheus `job` label equals the Service name (`notes-api`), which the SLO queries in `docs/slo.md` assume.
- Dev/prod hostnames are placeholders replaced by Terraform when the AWS stacks exist (Phase 13).

---

### P-005 — `notes-app` module and `local/30-apps` stack (Phase 8)

- **Date:** 2026-10-11
- **Phase / story:** Phase 8 / S5
- **Goal:** `notes` namespace (PSA restricted), CNPG `Cluster` via the official chart (1 instance, local-path PVC, operator-generated Secret), image in the local registry, Notes API release; `task up` / `task down` over all three stacks.
- **Mode:** research → generate → validate → push → plan → apply → test → **`task down` + `task up` from zero** → test → re-run

**Prompt**

> lets go with Phase 8: Stack local/30-apps

**Commits**

- Raw AI output: _fill in_
- Human corrections: _fill in_

**Verified before writing code**

| Question | Finding | Effect |
|---|---|---|
| CNPG `cluster` chart defaults | PostgreSQL **16** floating tag; `enablePDB: true`; `enableSuperuserAccess: true` | Pinned `postgresql:18.6-minimal-trixie@sha256:…` (same as Compose); PDB only with >1 instance, because a single-instance PDB blocks draining its node (Phase 9 check 9); no superuser Secret |
| CNPG network needs | Operator → pods on 8000 + 5432; instances ↔ each other; instance manager → Kubernetes API | Database ingress/egress policies, API server allowed via its EndpointSlice addresses (policies match after Service DNAT) |
| kind storage | `standard` StorageClass, local-path, `WaitForFirstConsumer` | `storage_class = "standard"` |

**Validation results**

| Step | Result | Notes |
|---|---|---|
| validate / tflint / trivy | ✅ | — |
| plan + apply | ✅ | DB release "completed" in **1 s**; the readiness gate then waited **34 s** for PostgreSQL before the API and its migration hook |
| `apps:check` (9 checks) | ✅ | CRUD through `https://api.localtest.me`, exact digest running, no password in state |
| re-plan | ✅ | no changes |
| `task down` (first destroy of 30-apps and 20-platform) | ✅ | 6 + 46 + 5 destroyed, `cluster:check-clean` passes |
| `task up` from zero | ✅ | **8.5 minutes**, 57 resources; all 26 checks across the three stacks pass |
| re-run `task apps:up` (build + push + apply) | ✅ after fix | `No changes` (correction 2) |

**Corrections and why**

| # | What the AI produced | What changed | Why |
|---|---|---|---|
| 1 | `platform:check` asserted the cluster's Helm releases were *exactly* the platform's | Assert each platform release is deployed | With the app installed there are 11 releases. Caught by running all checks on the fresh environment. |
| 2 | Image built with `BUILD_DATE=now` and BuildKit's default provenance | Commit-time `SOURCE_DATE_EPOCH`/`BUILD_DATE`, `--provenance=false` locally | The same commit produced a **new digest on every build** (observed: `a1113c…` vs `c7eea1…`), so every `task apps:up` caused a rollout and Phase 9's "re-apply shows no changes" could never pass. Two test builds proved commit timestamps alone are not enough — provenance attestations embed build times. CI publishes provenance/SBOM separately. |

**Design decisions made up front**

- Helm does not wait for custom resources, so a read-only `kubectl wait` gate sits between the database and the API (the measured 1 s vs 34 s confirms it was needed).
- Deploy by **digest** read back from the registry, so a rebuilt `-dirty` tag can never be served stale.
- The database's own network policies live with the database (see P-004 correction 1).

**Assumptions / uncertainties**

- The gate shells out to `kubectl` with the 10-cluster context; on AWS the same module needs the EKS context name (it is a variable).
- Persistence across pod deletion, isolation from other pods, HPA, rollback and drain are proven in Phase 9.

---

### P-006 — Local validation suite `task test` (Phase 9)

- **Date:** 2026-10-11
- **Phase / story:** Phase 9 / S4, S5, S6
- **Goal:** prove the 10 functional checks with one scripted, repeatable suite, passing from a fresh `task down && task up`.
- **Mode:** design review of each check against the running system → generate → run piecewise → run from zero (**failed**) → diagnose → fix → run from zero

**Prompt**

> lets go with Phase 9: Local validation suite (Functionality criterion)

**Commits**

- Raw AI output: _fill in_
- Human corrections: _fill in_

**Final evidence (fresh `task up` → `task down` → clean check → `task up` → `task test`, 31.6 min)**

| # | Check | Result |
|---|---|---|
| 1 | API reachable from outside | 200 through the gateway, TLS verified against the local CA |
| 2 | DB not reachable from outside | only non-ClusterIP Service is Envoy; no route or node port for 5432; host connect fails |
| 3 | Only the API reaches the DB | unlabelled pod in `notes` and pod in `default`: DNS OK, 5432 **timeout**; API pod: connected |
| 4 | Persistence | note survives deleting the PostgreSQL pod (new UID, same PVC) |
| 5 | Multiple replicas | 60 requests served by 3 pods (21/20/19) |
| 6 | Autoscaling | HPA 2 → 3 under k6 (224,244 requests, 0% failed, p95 56 ms), back to 2 |
| 7 | Modification | Terraform-applied message change, rolling update, 0 errors / 153 requests |
| 8 | Rollback | `helm rollback`, 0 errors / 73 requests; Terraform reconciles afterwards |
| 9 | Resilience | drained a worker hosting 1 API + 1 Envoy pod, 0 errors / 133 requests |
| 10 | Idempotency | `plan -detailed-exitcode` = 0 on all three stacks after checks 5–9 changed things |

**Corrections and why**

| # | Problem | Found by | Fix |
|---|---|---|---|
| 1 | Envoy Gateway ran **one** proxy replica without a PDB — draining its node would cut all traffic | design review before writing check 9 | `EnvoyProxy`: 2 replicas, topology spread, PDB `minAvailable: 1` (module input `gateway.replicas`) |
| 2 | Draining the database's node (local-path PV is node-bound) would stop PostgreSQL and make every API pod unready | design review | Check 9 drains the worker **without** the database; limitation documented (EBS + 3 instances on AWS) |
| 3 | After one drain, all pods sat on the other worker, so later drain runs passed while disrupting **nothing** | noticing "API pods: 0, Envoy pods: 0" in a passing run | The check respreads pods first and fails as *inconclusive* instead of passing vacuously |
| 4 | First fresh run: **8 of 55 requests failed** during the drain; not reproducible in 4 targeted reruns | the suite | Monitor now records status, curl exit code and timing for every request. Mitigations for the most plausible cause (Envoy keeps routing to a pod for a moment after it stopped): gateway retries only for requests that never reached a pod (`connect-failure`, `refused-stream`, `reset-before-request` — safe for POST), and `preStop` 5 s → 10 s. **Root cause not proven.** The final fresh run passed with 0 errors. |
| 5 | Second fresh run: **`task down` hung** — Envoy pods stuck `Terminating`, `gateway` namespace never deleted | the suite's `task down` step | Kubelet log: `KillPodSandbox … plugin type="calico" failed (delete) … Unauthorized`. Terraform had uninstalled **Calico before deleting the namespaces** (no dependency declared), so pod networking could not be torn down. Every non-Calico namespace now `depends_on` the Calico release (`tigera-operator` split out, with a `moved` block). Verified: namespaces destroyed first, Calico last, teardown clean. It had worked in Phase 8 by timing luck. |
| 6 | `platform:check` required *exactly* the platform's releases | running all checks after Phase 8 | asserts each platform release instead (P-005) |

**Lessons**

- A green run is not proof: two of the bugs (3 and 5) only showed on repeated runs from zero, which is why the plan insists on `task down && task up`.
- Destroy paths deserve the same testing as create paths; the CNI ordering bug was invisible to every `apply`.
- When a failure cannot be reproduced, say so: correction 4 is mitigated and monitored, not "fixed".

---

### P-007 — Observability as code (Phase 10)

- **Date:** 2026-10-11
- **Phase / story:** Phase 10 / S7
- **Goal:** dashboard, saved log query, alerts (API down, 5xx, PVC, crash loop), SLO recording rules and burn-rate alerts — all as code — with proof that load shows on the dashboard, an induced failure fires an alert and logs are searchable.
- **Mode:** inspect live metrics → generate → promtool check + unit tests → deploy → live checks (**1 failure**) → fix → re-run

**Prompt**

> Lets go with Phase 10: Observability (SRE practices)

**Commits**

- Raw AI output: _fill in_
- Human corrections: _fill in_

**Verified against the live system before writing queries**

| Question | Finding | Effect |
|---|---|---|
| API metric labels | `job="notes-api"`, as `slo.md` assumed | SLIs use `job` + route-template `handler` |
| Histogram buckets | `0.3` exists | latency SLI uses `le="0.3"` exactly |
| PVC usage metrics | **`kubelet_volume_stats_*` absent cluster-wide** (local-path volumes are host dirs) | the standard PVC alert would never fire locally → fallback to CNPG database size ÷ PVC request, with both paths unit-tested |
| DB connections | `cnpg_backends_total` with `application_name="notes-api"` (set in the app in Phase 4) | dashboard separates API connections from the exporter's |
| Waiting-reason metric | only exists while a container waits | crash-loop alert uses restart counts instead |
| Grafana provisioning | sidecar label `grafana_dashboard=1`, all namespaces; datasource UIDs `prometheus`, `loki` | dashboard ConfigMap in `notes`, fixed UIDs |
| promtool | not installed | `prom/prometheus:v3.15.0@sha256:…` — same version the cluster runs |

**Validation results**

| Check | Result |
|---|---|
| `promtool check rules` | 19 rules (12 recording, 7 alerts) |
| `promtool test rules` (13 cases) | ✅ after fixing 2 errors in the test data (float equality; `/health` vs the excluded `/healthz`) |
| live: rule groups healthy, dashboard + datasources served | ✅ |
| live: k6 load visible | 596 req/s recorded; **all 19 dashboard queries return data** (after correction 1) |
| live: logs searchable | LogQL by namespace + pod + JSON fields → access lines |
| live: induced failure | API scaled to 0 → `NotesApiDown` firing in Alertmanager with its runbook link → resolved after restore |
| re-plan all stacks | no changes |

**Corrections and why**

| # | What the AI produced | Found by | Fix |
|---|---|---|---|
| 1 | Error-ratio recording rules `sum(rate(5xx)) / sum(rate(all))` | the live check evaluating *every* dashboard query | With zero 5xx ever, the 5xx series does not exist, so the ratio was **empty, not 0**: a healthy service showed "No data" on its error panel (the stat panel only worked because of an `or vector(0)` patch). Numerators now use `or vector(0)`; promtool tests pin both edge cases (no errors → 0, no traffic → no value). |
| 2 | Runbook alert section written before the rules | review against the deployed rules | Referenced a non-existent `NotesDbUnavailable`, wrong timings, one "SloBurn" section for three alerts. Rewritten from the rules; every `runbook_url` anchor resolves. |

**Assumptions / uncertainties**

- No Alertmanager receiver locally; routing to Slack/PagerDuty (with the webhook in a Secret) belongs to the AWS work.
- Dashboard JSON is generated; Grafana edits must be exported back to the repository.

---

## 4. Validation summary

| Slice | validate | tflint | checkov/trivy | helm lint | kubeconform | Applied | Tests |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

## 5. Corrections summary

Aggregated from the prompt log: the most important before/after diffs, with links to the correction commits.

| Category | Example | Commit |
|---|---|---|
| Hallucinated / deprecated argument | | |
| Security (IAM, securityContext, exposure) | | |
| Hardcoded values / `latest` tags | | |
| Provider config in modules / cross-stack cycles | | |
| Missing probes / limits | | |

## 6. Edge cases, security and compliance

- **CRD ordering:** _how the generated code handled CRDs vs CRs, and what I fixed._
- **Destroy order:** _orphaned PVCs / load balancers; what protects against them._
- **Secrets in state:** _did the AI introduce `random_password` or literal secrets? Outcome._
- **IAM scope:** _wildcards found and narrowed._
- **Exposure:** _anything public besides the gateway?_
- **Encryption at rest:** _EBS, S3, KMS for EKS secrets._
- **NetworkPolicies:** _tested, not assumed (Phase 9 check #3)._

## 7. Performance, cost and idiomatic use

- **Infracost:** dev ≈ _$/month_, prod ≈ _$/month_ (date, assumptions).
- **Sizing:** node sizes vs pod requests; HPA thresholds.
- **Idiomatic use:** official `terraform-aws-modules`, `for_each` over `count`, pinned versions, small composable modules, `values.schema.json`.

## 8. Lessons learned

At least 2–3 honest stories where the AI got something wrong, how it was caught, and what changed in the process (e.g. a new rule in `CLAUDE.md`).

1. _…_
2. _…_
3. _…_
