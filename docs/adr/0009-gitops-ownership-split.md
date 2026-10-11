# ADR-0009: GitOps ownership split

- **Status:** Proposed
- **Date:** 2026-10-11
- **Related:** S9, ADR-0002

## Context

Terraform is good at provisioning infrastructure and platform components with clear dependencies. It is weaker at continuous application delivery: every app change needs a `terraform apply`, and drift caused by in-cluster changes is detected only at the next plan. Argo CD continuously reconciles the cluster against Git and gives a clear history of app deployments.

Having both tools manage the same resource causes fights over ownership, so the boundary must be explicit.

## Decision

Adopt **Argo CD** as an evolution step (Phase 12), with this split:

| Owner | Resources |
|---|---|
| **Terraform** | Cluster (`10-cluster`), all platform add-ons including Argo CD itself (`20-platform`), the `notes` namespace and the CNPG `Cluster` (`30-apps`) |
| **Argo CD** | The Notes API Helm release (and future app releases), driven by an app-of-apps / ApplicationSet in `gitops/` |

- Terraform bootstraps Argo CD and the root Application only; it never manages child Applications.
- Each resource has exactly one owner. When the Notes API moves to Argo CD, its `helm_release` is removed from `30-apps` (with `terraform state rm` or a `removed` block, so the running release is not destroyed).
- Image tag promotion: CI updates the tag in the environment values in Git; Argo CD syncs.
- Before Phase 12, `30-apps` owns the Notes API release.

## Alternatives considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| Terraform for everything | One tool | Slow app delivery loop; no continuous reconciliation | Kept only until Phase 12 |
| Argo CD for everything, including platform | Pure GitOps | Bootstrapping problem; CRD and ordering logic moves into sync waves | Terraform already handles ordering well |
| Flux | Lightweight, GitOps native | No UI for the demo | Argo CD demos better |

## Consequences

**Positive**

- App changes reach the cluster with a merged PR and no manual apply.
- Clear, reviewable ownership boundary.

**Negative / trade-offs**

- Two tools to understand; the boundary must be respected.
- The migration step from `30-apps` to Argo CD needs care to avoid downtime.
