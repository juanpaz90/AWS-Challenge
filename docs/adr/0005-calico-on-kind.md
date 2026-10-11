# ADR-0005: Calico as the CNI on kind

- **Status:** Accepted
- **Date:** 2026-10-11
- **Related:** S3, S6, ADR-0001

## Context

The core security requirement is that only the API can reach the database. We prove this with NetworkPolicies, so the CNI must **enforce** them. kind's default CNI (`kindnet`) has only recently gained basic NetworkPolicy support and is not what we run on EKS, so we do not want to rely on it for the security proof.

On EKS, the VPC CNI supports NetworkPolicies natively when its network policy agent is enabled.

## Decision

Disable kind's default CNI and install **Calico** (via the Tigera operator Helm chart) as the first component of `20-platform`.

- Nodes stay `NotReady` after `10-cluster` until Calico is installed (expected).
- We use only standard `networking.k8s.io/v1` NetworkPolicy objects, never Calico-specific CRDs, so the same policies work with the VPC CNI on EKS.
- The `calico-system` namespace gets a documented Pod Security exception (Calico needs privileged host networking).

NetworkPolicies in `notes`:

1. Default deny ingress and egress.
2. Allow gateway (Envoy proxy pods) → API on the app port.
3. Allow API → DB on 5432.
4. Allow CNPG operator → DB (status/management port).
5. Allow monitoring (Prometheus) → metrics ports.
6. Allow DNS egress to `kube-system` (CoreDNS).

## Alternatives considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| kindnet (default) | Zero setup | Limited policy support; not used anywhere else | Not trusted for the security proof |
| Cilium | eBPF, Gateway API, Hubble | Heavier; overlaps with Envoy Gateway; differs from EKS default | More than we need |
| Flannel | Light | No NetworkPolicy enforcement | Fails the core requirement |

## Consequences

**Positive**

- NetworkPolicies are actually enforced and can be tested (Phase 9 check #3).
- Standard policies are portable to the EKS VPC CNI.

**Negative / trade-offs**

- One more component to install and pin; nodes are not Ready until it is installed.
- CNI differs between local (Calico) and AWS (VPC CNI). Behaviour is equivalent only for standard NetworkPolicy features, so we stay within them.

**Follow-ups**

- Add a negative test (throwaway pod cannot reach 5432) and a positive test (API can) to `task test`.
