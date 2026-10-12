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
