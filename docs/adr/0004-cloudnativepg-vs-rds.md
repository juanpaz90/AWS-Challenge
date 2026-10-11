# ADR-0004: CloudNativePG (in-cluster) vs Amazon RDS

- **Status:** Accepted
- **Date:** 2026-10-11
- **Related:** S5, S6, ADR-0007

## Context

The exercise asks for a PostgreSQL database **on Kubernetes** with persistent storage, not reachable from outside. We also want:

- the same database setup locally and on AWS,
- no database password in Terraform state or Helm values,
- operational features (failover, backups) without writing them ourselves.

The Bitnami PostgreSQL chart was the common default, but Bitnami moved its catalog to a paid/secure-images model in 2025 and froze the free images, so it is no longer a safe long-term dependency.

## Decision

Run PostgreSQL with the **CloudNativePG (CNPG)** operator, installed in `20-platform`, and declare the database with the official CNPG `cluster` Helm chart in `30-apps`.

| | Local (kind) | AWS dev | AWS prod |
|---|---|---|---|
| Instances | 1 | 3 | 3 |
| Storage | `local-path` PVC | encrypted `gp3` (EBS CSI) | encrypted `gp3` |
| Backups | none | S3 via Barman Cloud | S3 via Barman Cloud + PITR |
| Credentials | operator-generated Secret | operator-generated Secret | operator-generated Secret (or External Secrets) |

The database is exposed only as ClusterIP Services (`-rw`, `-ro`) inside the `notes` namespace and protected by NetworkPolicies (ADR-0005).

**Amazon RDS for PostgreSQL is documented as the production alternative** and would be the default recommendation for a real production workload with no strict "on Kubernetes" requirement.

## Alternatives considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| Plain StatefulSet | No dependencies, easy to explain | No failover, backups or upgrades; we own all operations | Too much hand-rolled ops |
| Bitnami PostgreSQL chart | Familiar | Catalog distribution changes; image availability risk | Supply-chain risk |
| Zalando / Crunchy operators | Mature | Heavier, more moving parts | CNPG is lighter and CNCF |
| Amazon RDS | Fully managed, Multi-AZ, PITR, patching | Not "on Kubernetes"; no local equivalent; costs more | Kept as the documented prod alternative |

## Consequences

**Positive**

- One declarative `Cluster` resource gives failover, rolling updates and backups.
- Credentials are created by the operator inside the cluster and never touch Terraform state.
- Same chart locally and on AWS; only values change.

**Negative / trade-offs**

- We operate the database ourselves on AWS (upgrades, storage sizing, backups testing), which RDS would handle.
- Locally, a single instance on `local-path` storage means data is lost if the node is lost (acceptable for local).
- CNPG CRDs add ordering requirements (handled by ADR-0002).

**Follow-ups**

- Document the RDS migration path: swap the CNPG `Cluster` for an RDS module in `10-cluster`, keep the app's Secret contract (`host`, `port`, `username`, `password`, `dbname`) the same.
