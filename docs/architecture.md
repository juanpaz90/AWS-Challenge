# Architecture

> Local-first, cloud-ready. The same Helm charts and platform layer run on a Terraform-managed `kind` cluster and on AWS EKS; only the cluster layer changes. Decisions are recorded in the [ADRs](adr/README.md).

## 1. System context

```mermaid
flowchart LR
    user([Client<br/>browser / curl / k6])
    dev([Engineer])
    ci([GitHub Actions])

    subgraph platform[Kubernetes platform]
        gw[Envoy Gateway]
        api[Notes API]
        db[(PostgreSQL<br/>CloudNativePG)]
        obs[Prometheus · Grafana · Loki]
    end

    user -- HTTPS api.localtest.me --> gw --> api --> db
    dev -- HTTPS grafana.localtest.me --> gw --> obs
    dev -- terraform / task --> platform
    ci -- build · scan · e2e --> platform
```

Only the gateway accepts traffic from outside the cluster. The database has no external entry point.

## 2. Local topology (kind)

```mermaid
flowchart TB
    client([Client]) -->|"80/443 → 127.0.0.1"| host

    subgraph host[Docker host — all created by Terraform]
        reg[[Local registry<br/>localhost:5001]]

        subgraph kind[kind cluster: 1 control plane + 2 workers]
            pm[extraPortMappings 80/443] --> np

            subgraph ns_gw[ns: gateway]
                np[Envoy proxy<br/>NodePort]
            end

            subgraph ns_notes[ns: notes — PSA restricted]
                route{{HTTPRoute<br/>TLS via cert-manager}}
                svc[notes-api Service<br/>ClusterIP]
                pods[Notes API pods<br/>Deployment + HPA + PDB]
                job[Migration Job<br/>Helm hook]
                dbsvc[notes-db-rw<br/>ClusterIP]
                db[(PostgreSQL<br/>CNPG Cluster)]
                pvc[(PVC<br/>local-path)]
            end

            subgraph ns_plat[platform namespaces]
                calico[Calico]
                cm[cert-manager]
                ms[metrics-server]
                cnpg[CNPG operator]
            end

            subgraph ns_mon[ns: monitoring]
                prom[Prometheus + Alertmanager]
                graf[Grafana]
                loki[Loki]
                alloy[Alloy DaemonSet]
            end
        end
    end

    np --> route --> svc --> pods
    pods -->|5432| dbsvc --> db --- pvc
    job -->|5432| dbsvc
    cnpg -.manages.-> db
    prom -.scrapes.-> pods
    alloy -.ships logs.-> loki
    reg -.image pulls.-> pods
```

## 3. Network security model

### 3.1 Exposure rules

| Component | Service type | External exposure |
|---|---|---|
| Envoy Gateway proxy | NodePort (local) / LoadBalancer → NLB (AWS) | **Yes** — the only entry point |
| Notes API | ClusterIP | Only via `HTTPRoute` |
| Grafana | ClusterIP | Only via `HTTPRoute` (`grafana.localtest.me`) |
| PostgreSQL | ClusterIP | **Never** — no route, NodePort or LoadBalancer |

### 3.2 NetworkPolicies in `notes`

Default deny for ingress and egress, then explicit allows ([ADR-0005](adr/0005-calico-on-kind.md)):

```mermaid
flowchart LR
    gw[gateway ns<br/>Envoy proxy] -->|app port| api[Notes API]
    mon[monitoring ns<br/>Prometheus] -->|metrics port| api
    mon -->|9187| db
    api -->|5432| db[(PostgreSQL)]
    job[Migration Job] -->|5432| db
    op[cnpg-system ns<br/>operator] -->|8000 status| db
    api -->|53 UDP/TCP| dns[kube-system<br/>CoreDNS]
    db -->|53| dns
    other[Any other pod] -. denied .-x db
```

> Exact ports and pod labels are confirmed against the pinned chart versions when the policies are written (Phase 7) and proven by Phase 9 check #3.

### 3.3 Namespaces and Pod Security Admission

| Namespace | Contents | PSA level |
|---|---|---|
| `notes` | Notes API, migration Job, CNPG `Cluster` | `restricted` |
| `gateway` | Envoy Gateway controller + proxies | `restricted` (verified in Phase 6) |
| `cert-manager` | cert-manager | `restricted` |
| `cnpg-system` | CNPG operator | `restricted` |
| `monitoring` | Prometheus stack, Loki, Alloy | `privileged` — **documented exception**: node-exporter needs hostNetwork/hostPID/hostPath. Alloy tails logs through the API server and needs no host access. |
| `tigera-operator` (+ `calico-system`, managed by the operator) | Calico | `privileged` — **documented exception** (CNI needs host networking) |

All Terraform-created namespaces also set `warn` and `audit` to `restricted`, so any gap stays visible.

### 3.4 Workload hardening (Notes API)

- Non-root UID, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, all capabilities dropped, `seccompProfile: RuntimeDefault`.
- Requests and limits on every container.
- Startup, liveness (`/healthz`) and readiness (`/readyz`, checks DB) probes.
- `PodDisruptionBudget` (`minAvailable: 1`) and topology spread across nodes.
- `automountServiceAccountToken: false` unless needed.

## 4. Terraform layout

Three stacks per environment, each with its own state, applied in order and destroyed in reverse ([ADR-0002](adr/0002-three-stack-terraform-layout.md)).

```mermaid
flowchart LR
    subgraph s10[10-cluster]
        c1[Registry container]
        c2[kind cluster<br/>AWS: VPC · EKS · ECR · IAM]
    end
    subgraph s20[20-platform]
        p1[Calico] --> p2[cert-manager<br/>+ ClusterIssuer] --> p3[Envoy Gateway<br/>+ Gateway] --> p4[metrics-server] --> p5[CNPG operator] --> p6[Observability] --> p7[(Argo CD)]
    end
    subgraph s30[30-apps]
        a1[notes namespace] --> a2[CNPG Cluster] --> a3[Notes API release<br/>HTTPRoute · HPA · PDB · NetPol]
    end
    s10 -- kubeconfig / context --> s20 -- CRDs exist --> s30
```

| Stack | Applies | State (local) | State (AWS) |
|---|---|---|---|
| `10-cluster` | Cluster + registry | local file | `s3://<bucket>/<env>/10-cluster/terraform.tfstate` |
| `20-platform` | Controllers + CRDs | local file | `s3://<bucket>/<env>/20-platform/terraform.tfstate` |
| `30-apps` | Namespace, DB, app | local file | `s3://<bucket>/<env>/30-apps/terraform.tfstate` |

Image builds stay out of Terraform: `task build` pushes `localhost:5001/notes-api:<git-sha>` and the tag is passed to `30-apps` as a variable.

## 5. Request and deployment flows

### 5.1 Request path

```mermaid
sequenceDiagram
    participant C as Client
    participant E as Envoy (gateway)
    participant A as Notes API pod
    participant P as PostgreSQL (rw)
    C->>E: HTTPS GET api.localtest.me/notes
    E->>E: TLS termination (cert-manager cert)
    E->>A: HTTP via HTTPRoute → Service
    A->>P: SQL on 5432 (credentials from CNPG Secret)
    P-->>A: rows
    A-->>E: 200 JSON (+ pod name)
    E-->>C: 200
```

### 5.2 Delivery path

```mermaid
flowchart LR
    pr[PR] --> checks[Lint · validate · scan<br/>build image · trivy]
    checks --> e2e[Ephemeral kind<br/>task up · task test]
    e2e --> merge[Merge to main]
    merge --> push[Push image :git-sha]
    push --> bump[Update tag in env values]
    bump --> deploy{Phase}
    deploy -->|before Phase 12| tf[terraform apply 30-apps]
    deploy -->|Phase 12+| argo[Argo CD sync]
```

## 6. Local → AWS mapping

| Concern | Local (kind) | AWS (EKS) |
|---|---|---|
| Cluster | kind + Docker | VPC (2–3 AZs, public/private subnets) + EKS managed node groups |
| CNI / NetworkPolicy | Calico | VPC CNI with network policy enabled |
| Storage | `local-path` PVC | EBS CSI driver + encrypted `gp3` StorageClass |
| Registry | `registry:2` container | ECR (scan on push, immutable tags) |
| Edge | NodePort + `extraPortMappings` | AWS Load Balancer Controller → NLB in front of Envoy |
| TLS | cert-manager self-signed CA | ACM, or cert-manager + Let's Encrypt |
| Secrets | CNPG-generated Secrets | External Secrets Operator + Secrets Manager (Pod Identity) |
| Terraform state | Local files | S3 with native locking, versioning, encryption |
| Database | CNPG, 1 instance | CNPG, 3 instances + S3 backups (RDS as documented alternative) |
| CI credentials | n/a | GitHub OIDC → IAM role |

### 6.1 AWS dev topology

```mermaid
flowchart TB
    inet([Internet]) --> nlb[NLB<br/>public subnets]
    subgraph vpc[VPC — 2-3 AZs]
        nlb --> envoy
        subgraph priv[Private subnets]
            subgraph eks[EKS — private endpoint / restricted CIDR]
                envoy[Envoy Gateway] --> api[Notes API]
                api --> db[(CNPG 3 instances<br/>gp3 encrypted)]
            end
        end
        nat[NAT gateway<br/>1 in dev, 1 per AZ in prod]
    end
    priv --> nat --> inet
    db -.backups.-> s3[(S3)]
    ecr[(ECR)] -.pull.-> api
    sm[(Secrets Manager)] -.External Secrets.-> api
```

## 7. Related documents

- [User story and epic](user-story.md)
- [ADRs](adr/README.md)
- [SLOs](slo.md)
- [Runbook](runbook.md)
- [GenAI log](genai.md)
- [Project plan](project-plan.md)
