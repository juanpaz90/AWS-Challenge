# Architecture Decision Records

We record significant architecture decisions using a lightweight [MADR](https://adr.github.io/madr/)-style format. Each ADR states the context, the decision, the alternatives considered and the consequences.

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-kind-terraform-local.md) | kind + Terraform for the local environment | Accepted |
| [0002](0002-three-stack-terraform-layout.md) | Three-stack Terraform layout | Accepted |
| [0003](0003-envoy-gateway-over-ingress-nginx.md) | Envoy Gateway / Gateway API over ingress-nginx | Accepted |
| [0004](0004-cloudnativepg-vs-rds.md) | CloudNativePG (in-cluster) vs Amazon RDS | Accepted |
| [0005](0005-calico-on-kind.md) | Calico as the CNI on kind | Accepted |
| [0006](0006-observability-stack.md) | Observability stack: in-cluster Grafana, Loki and Alloy | Accepted |
| [0007](0007-secrets-strategy.md) | Secrets strategy | Accepted |
| [0008](0008-terraform-state-backend.md) | Terraform state backend | Accepted |
| [0009](0009-gitops-ownership-split.md) | GitOps ownership split | Proposed |

## Process

1. Copy [`template.md`](template.md) to `NNNN-short-title.md` with the next number.
2. Open a PR with status **Proposed**.
3. Change the status to **Accepted** on merge.
4. Never edit an accepted ADR's decision. To change it, write a new ADR and mark the old one **Superseded by ADR-NNNN**.

ADRs are written by a human. AI may help with wording, but the decision and its trade-offs are not delegated (see [`project-plan.md` §8.6](../project-plan.md#86-do-not-delegate)).
