# Generative AI in this project

> Evidence for the exercise's Generative AI section. Updated continuously and finalised in Phase 15. Story: S11.
> Principle: **I am the architect; Claude is the pair-programmer working inside my guardrails.** Architecture, ADRs, security boundaries, final review and the `apply` decision are not delegated.

## 1. Tool and setup

| Item | Value |
|---|---|
| Assistant | Claude Code (CLI), model: _fill in_ |
| Project rules | [`CLAUDE.md`](../CLAUDE.md) — architecture, conventions, hard rules, definition of done |
| Context sources | ADRs in [`adr/`](adr/README.md), [`architecture.md`](architecture.md), [`project-plan.md`](project-plan.md) |
| Up-to-date docs | Terraform MCP server: _yes/no_ |
| Permissions | Allowed: read files, `fmt`, `validate`, `tflint`, `trivy`, `checkov`, `helm lint`/`template`, `kubeconform`, `kubectl get`/`describe`. **Require approval:** `terraform apply`/`destroy`, `helm install`/`upgrade`/`uninstall`, any `kubectl` write. |
| Credentials | No AWS credentials in the Claude session. |

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

_None yet._

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
