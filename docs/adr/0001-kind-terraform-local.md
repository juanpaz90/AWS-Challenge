# ADR-0001: kind + Terraform for the local environment

- **Status:** Accepted
- **Date:** 2026-10-11
- **Related:** S2, ADR-0002, ADR-0005

## Context

The exercise requires an API (multiple replicas) and a PostgreSQL database with persistent storage on Kubernetes, fully defined as code. Building directly on EKS is slow to iterate on and costs money every hour. We need a local environment that:

- is created and destroyed only by code (no manual `kind create cluster`),
- behaves close enough to EKS that the same Helm charts and platform layer can be reused,
- supports multiple nodes (for topology spread, PDB and drain tests),
- enforces NetworkPolicies, so database isolation can be proven.

## Decision

Use **kind** (Kubernetes in Docker) for the local cluster, managed entirely by **Terraform** with the community `tehcyx/kind` provider, and the `kreuzwerker/docker` provider for the local image registry.

- Topology: 1 control plane + 2 workers.
- The node image is pinned to the **same Kubernetes minor version** as the target EKS version.
- The default CNI is disabled (Calico is installed instead, see ADR-0005).
- `extraPortMappings` expose host ports 80/443 to the gateway NodePort.
- A `registry:2` container on the kind network acts as the local ECR equivalent (`localhost:5001`), wired in through the containerd mirror config.
- Hostnames use `*.localtest.me`, which resolves to `127.0.0.1` with no hosts-file edits.

## Alternatives considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| `kind` CLI + shell script | Simple, official tooling | Imperative; breaks the "everything as code" rule; no state or drift detection | Not declarative |
| minikube | Mature, addons | Single node by default; addons diverge from EKS; driver differences across OSes | Weaker parity and multi-node story |
| k3d / k3s | Fast, light, built-in registry | k3s is a different distribution (Traefik, flannel, local-path built in) and drifts from upstream | Less parity with EKS |
| Docker Desktop Kubernetes | Zero setup | Single node, not reproducible as code, version tied to Docker Desktop | Not reproducible |
| EKS only | Real target | Cost, slow feedback loop, needs credentials early | Too expensive for iteration |

## Consequences

**Positive**

- One tool (Terraform) declares every resource from the cluster up; `apply`/`destroy` are reproducible and drift is visible.
- Multi-node behaviour (spread, PDB, drain) can be demonstrated locally.
- No cloud cost during development; the same flow runs in CI on an ephemeral cluster.

**Negative / trade-offs**

- `tehcyx/kind` is a community provider. We pin it exactly and keep the module thin, so it is easy to replace.
- kind has no real load balancer or cloud storage; we use NodePort + port mappings and `local-path` volumes. A PVC on `local-path` is tied to one node, so losing that node loses the data (accepted locally; on AWS EBS volumes are used).
- metrics-server needs the insecure kubelet TLS flag on kind (local only, documented).
- Docker needs ≥ 8 GB RAM once observability runs.

**Follow-ups**

- Verify the latest kind node image for the chosen EKS minor version in Phase 0.
- Document `cloud-provider-kind` as a Linux alternative for `LoadBalancer` Services.
