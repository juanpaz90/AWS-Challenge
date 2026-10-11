# ADR-0008: Terraform state backend

- **Status:** Accepted
- **Date:** 2026-10-11
- **Related:** S2, S10, ADR-0002, ADR-0007

## Context

Each environment has three stacks (ADR-0002), each with its own state. Locally, state only describes throwaway resources on one laptop. On AWS, state is shared (developers and CI), must be locked against concurrent applies, and must be recoverable.

Since Terraform 1.10, the S3 backend supports **native locking** with a lock file in the bucket (`use_lockfile = true`), and DynamoDB-based locking is deprecated.

## Decision

| Environment | Backend |
|---|---|
| `local` | **Local** state files (gitignored), one per stack |
| `dev`, `prod` | **S3** backend with `use_lockfile = true` (native locking), bucket versioning, SSE-KMS encryption, public access blocked, TLS-only bucket policy |

- The S3 bucket is created by a separate `infra/bootstrap` stack, which itself uses local state (chicken-and-egg). Its state is kept small and the bucket has `prevent_destroy`.
- State keys follow `<env>/<stack>/terraform.tfstate`, e.g. `dev/20-platform/terraform.tfstate`.
- Stacks read each other's outputs with `terraform_remote_state` (read-only).
- Access to the bucket is limited to the CI OIDC role and named admin roles.

## Alternatives considered

| Option | Pros | Cons | Why not chosen |
|---|---|---|---|
| S3 + DynamoDB lock table | Long-standing pattern | Extra resource; deprecated in favour of native locking | Superseded |
| HCP Terraform | Managed state, UI, runs | External SaaS account; vendor dependency | Not needed |
| Local state everywhere | Simple | No sharing, locking or recovery | Unsafe for shared envs |

## Consequences

**Positive**

- Locking, versioning (rollback of corrupted state) and encryption at rest with one resource.
- Requires Terraform ≥ 1.10, which we pin in `versions.tf`.

**Negative / trade-offs**

- `bootstrap` state is local and must be handled carefully.
- State still contains non-secret infrastructure details, so bucket access stays restricted.
