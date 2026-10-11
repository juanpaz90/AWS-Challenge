# ADR-0002: Three-stack Terraform layout

- **Status:** Accepted
- **Date:** 2026-10-11
- **Related:** S2, S3, S5, S10, ADR-0008, ADR-0009

## Context

The `helm` and `kubernetes` Terraform providers need a working cluster endpoint and credentials at plan time. When the cluster is created in the same apply, provider configuration depends on unknown values, which leads to failed plans, unreliable refreshes and destroy-order problems.

Separately, Kubernetes CRDs (cert-manager, Gateway API, CloudNativePG, Prometheus Operator) must exist before any resource that uses them can be planned. The `kubernetes_manifest` resource validates against the live API server at plan time, so a CRD and its custom resources cannot be in the same first apply.

Finally, the layers change at different rates: the cluster rarely, the platform occasionally, the application often.

## Decision

Split each environment into **three root stacks**, each with **its own state**, applied in order and destroyed in reverse:

| Stack | Contents |
|---|---|
| `10-cluster` | Registry container + kind cluster (AWS: VPC, EKS, ECR, IAM). Outputs kubeconfig / cluster endpoint and context name. |
| `20-platform` | Calico → cert-manager → Envoy Gateway → metrics-server → CNPG operator → observability → (Argo CD). Installs controllers and **CRDs**. |
| `30-apps` | `notes` namespace, CNPG `Cluster`, Gateway/HTTPRoute, Notes API Helm release. Uses the CRDs. |

Rules:

- Reusable modules live in `infra/modules/`; `infra/environments/<env>/<stack>/` contains **wiring and `tfvars` only**.
- Providers are configured **only** in root stacks, never in modules.
- Stacks exchange data through outputs and `terraform_remote_state` (or a shared kube context name), never through hardcoded values.
- The task runner wraps the ordering: `task up` = 10 → 20 → 30; `task down` = 30 → 20 → 10.

## Alternatives considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| Single root stack | One apply | Provider-from-unknown-cluster problems; CRD ordering fails on first plan; huge blast radius | Unreliable |
| Two stacks (cluster / everything else) | Fewer states | CRDs and their CRs still in the same apply | Doesn't solve CRD ordering |
| Terragrunt | DRY wiring, dependency graph | Extra tool and learning curve for reviewers | Not needed at this size; could be adopted later |
| Terraform Stacks / HCP | Native orchestration | Requires HCP; not available locally | Vendor dependency |

## Consequences

**Positive**

- Each apply has reliable, known provider configuration.
- CRDs always exist before resources that use them.
- Smaller blast radius: an app change cannot touch the cluster.
- `30-apps` can be handed over to Argo CD cleanly (ADR-0009).

**Negative / trade-offs**

- Three states and three applies per environment; ordering is enforced by the task runner, not by Terraform.
- Cross-stack outputs create coupling that must be kept stable.

**Follow-ups**

- Add a `task plan` target that plans all three stacks in order.
