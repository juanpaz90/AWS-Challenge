# Stack: local/10-cluster

First of the three local stacks ([ADR-0002](../../../../docs/adr/0002-three-stack-terraform-layout.md)). Wires the [`kind-cluster`](../../../modules/kind-cluster) module with the values in `terraform.tfvars` and exposes the cluster connection details that `20-platform` reads through `terraform_remote_state`.

```bash
task cluster:up            # terraform init + apply (add `-- -auto-approve` to skip the prompt)
task cluster:check         # nodes, version, port mappings, registry mirror
task cluster:down          # terraform destroy + remove generated node config
task cluster:check-clean   # nothing left behind
```

- **Kubernetes version:** `kindest/node:v1.35.0`, the newest image published for kind v0.31.0 (embedded in `tehcyx/kind 0.11.0`) and the same minor as the target EKS version (1.35, standard support until 2027-03-27).
- **State:** local file `terraform.tfstate` (gitignored). It contains the cluster-admin client key for this throwaway cluster, which is why it never leaves the machine.
- **Docker socket:** the docker provider ignores Docker CLI contexts, so the task resolves the active context's socket into `DOCKER_HOST`.
- **kubeconfig:** the context `kind-notes-local` is merged into `~/.kube/config` and removed on destroy.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.16.0, < 2.0.0 |
| docker | = 4.6.0 |
| kind | = 0.11.0 |
| local | = 2.9.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| kind\_cluster | ../../../modules/kind-cluster | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_name | Name of the kind cluster. | `string` | n/a | yes |
| node\_image | kindest/node image pinned by digest; Kubernetes minor matches the target EKS version. | `string` | n/a | yes |
| pod\_subnet | Pod CIDR, shared with the CNI configuration in 20-platform. | `string` | n/a | yes |
| port\_mappings | Host → node port mappings for the gateway NodePorts. | <pre>map(object({<br/>    container_port = number<br/>    host_port      = number<br/>    listen_address = optional(string, "127.0.0.1")<br/>    protocol       = optional(string, "TCP")<br/>  }))</pre> | n/a | yes |
| registry\_host\_port | Host port of the local registry (images are pushed to localhost:<port>). | `number` | n/a | yes |
| registry\_image | Registry image pinned by digest. | `string` | n/a | yes |
| worker\_count | Number of worker nodes. | `number` | n/a | yes |
| docker\_host | Docker daemon socket for the docker provider. null uses DOCKER\_HOST or the default socket. | `string` | `null` | no |
| kubeconfig\_path | Kubeconfig the cluster context is merged into; ~ is expanded. | `string` | `"~/.kube/config"` | no |
| labels | Labels applied to Docker resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| client\_certificate | Client certificate for the helm/kubernetes providers. |
| client\_key | Client key for the helm/kubernetes providers. |
| cluster\_ca\_certificate | API server CA certificate. |
| cluster\_name | Name of the kind cluster. |
| context\_name | kubectl context name (kubectl --context <value>). |
| endpoint | API server endpoint. |
| gateway\_node\_ports | NodePorts the gateway must expose so the host port mappings reach it. |
| kubeconfig\_path | Kubeconfig file containing the context. |
| kubernetes\_version | Kubernetes version of the nodes. |
| pod\_subnet | Pod CIDR, consumed by the Calico install in 20-platform. |
| registry\_host | Registry address for pushes and image references. |
<!-- END_TF_DOCS -->
