# ADR-0003: Envoy Gateway / Gateway API over ingress-nginx

- **Status:** Accepted
- **Date:** 2026-10-11
- **Related:** S3, S4, S5

## Context

The API must be reachable from outside the cluster; the database must not. We need an ingress layer that:

- works on kind (NodePort + port mappings) and on EKS (behind an NLB) with the same configuration,
- supports TLS with cert-manager,
- is actively maintained.

The Kubernetes community **retired ingress-nginx** (retirement announced in November 2025, with best-effort maintenance ending in March 2026). The **Gateway API** is the successor standard to the `Ingress` resource, with a role-oriented model: the platform team owns the `Gateway`, app teams own `HTTPRoute`s.

## Decision

Use **Envoy Gateway** as the Gateway API implementation.

- `20-platform` installs Envoy Gateway, the Gateway API CRDs, a `GatewayClass` and a shared `Gateway` in the `gateway` namespace with HTTP (80) and HTTPS (443) listeners.
- TLS certificates are issued by cert-manager (self-signed CA locally; ACM or Let's Encrypt on AWS).
- The Notes API chart ships an optional `HTTPRoute` attached to the shared `Gateway`.
- Locally, the Envoy proxy Service is a NodePort that matches the kind `extraPortMappings`. On AWS, the AWS Load Balancer Controller fronts it with an NLB.
- The database has **no** route, NodePort or LoadBalancer.

## Alternatives considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| ingress-nginx | Ubiquitous, well known | Retired; no further security fixes | Not acceptable for new work |
| Traefik | Mature, supports Gateway API | Primary model is its own CRDs | Envoy Gateway is a closer fit to upstream Gateway API |
| Istio / Cilium Gateway | Gateway API + mesh features | Much heavier; Cilium would replace Calico | Over-engineered for this scope |
| AWS ALB Ingress only | Native on AWS | No local equivalent; breaks local ≈ cloud | Not portable |

## Consequences

**Positive**

- Forward-looking, vendor-neutral API; the same manifests work locally and on EKS.
- Clear separation: platform owns `Gateway`, app owns `HTTPRoute`.
- NetworkPolicies can target the Envoy proxy pods precisely (gateway → API only).

**Negative / trade-offs**

- Gateway API is newer; some reviewers may be less familiar with it.
- Envoy Gateway creates proxy Deployments dynamically, so their labels must be checked when writing NetworkPolicies.

**Follow-ups**

- Verify the current Envoy Gateway release and its supported Gateway API version before pinning.
