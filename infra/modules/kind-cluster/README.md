# Module: kind-cluster

Creates the local Kubernetes cluster for the `local` environment, entirely from Terraform ([ADR-0001](../../../docs/adr/0001-kind-terraform-local.md)):

- a Docker network (`kind`), owned by Terraform so `destroy` removes it (kind itself never deletes its network);
- a `registry` container on that network, published on `127.0.0.1:<host_port>`, standing in for ECR;
- a kind cluster with one control-plane node and `worker_count` workers, the default CNI disabled (Calico comes in `20-platform`, [ADR-0005](../../../docs/adr/0005-calico-on-kind.md)), and host ports mapped to the gateway NodePorts;
- a containerd registry mirror so nodes pull `localhost:<host_port>/<image>` from the registry.

The mirror follows kind's local-registry guide, but declaratively: instead of `docker exec`-ing a `hosts.toml` into every node after creation, Terraform renders it into `generated_dir` and each node mounts that directory read-only at `/etc/containerd/certs.d`. `generated_dir` must therefore be visible to the Docker daemon (anything under `$HOME` works with Colima and Docker Desktop).

Nodes stay `NotReady` until a CNI is installed. `wait_for_ready` is deliberately `false`.

The module declares only `required_providers` with lower bounds; provider configuration and exact pins live in the root stack.

## Usage

```hcl
module "kind_cluster" {
  source = "../../../modules/kind-cluster"

  cluster_name    = "notes-local"
  node_image      = "kindest/node:v1.35.0@sha256:..."
  worker_count    = 2
  port_mappings   = { http = { container_port = 30080, host_port = 80 } }
  registry        = { image = "registry:3.1.2@sha256:..." }
  kubeconfig_path = pathexpand("~/.kube/config")
  generated_dir   = abspath("${path.module}/.generated")
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10.0 |
| docker | >= 4.6.0 |
| kind | >= 0.11.0 |
| local | >= 2.9.0 |

## Providers

| Name | Version |
| ---- | ------- |
| docker | 4.6.0 |
| kind | 0.11.0 |
| local | 2.9.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [docker_container.registry](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container) | resource |
| [docker_image.registry](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/image) | resource |
| [docker_network.kind](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/network) | resource |
| [kind_cluster.this](https://registry.terraform.io/providers/tehcyx/kind/latest/docs/resources/cluster) | resource |
| [local_file.registry_hosts](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_name | Name of the kind cluster. The kubectl context becomes kind-<cluster\_name>. | `string` | n/a | yes |
| generated\_dir | Absolute directory where generated node config (containerd registry hosts) is written. It must be visible to the Docker daemon, e.g. under $HOME with Colima or Docker Desktop. | `string` | n/a | yes |
| kubeconfig\_path | Absolute path of the kubeconfig file the cluster context is merged into. The context is removed again on destroy. | `string` | n/a | yes |
| node\_image | kindest/node image for every node, pinned by digest. Must be published for the kind version embedded in the provider, and match the EKS Kubernetes minor. | `string` | n/a | yes |
| registry | Local image registry (the ECR stand-in). Nodes pull localhost:<host\_port>/<image> through a containerd mirror to http://<name>:5000. | <pre>object({<br/>    image     = string<br/>    name      = optional(string, "kind-registry")<br/>    host_port = optional(number, 5001)<br/>  })</pre> | n/a | yes |
| disable\_default\_cni | Disable kindnet so a NetworkPolicy-enforcing CNI (Calico, ADR-0005) can be installed. Nodes stay NotReady until it is. | `bool` | `true` | no |
| labels | Labels applied to the Docker resources created by this module. | `map(string)` | `{}` | no |
| network\_name | Docker network shared by the kind nodes and the registry. kind reuses an existing network with this name, so Terraform owns its lifecycle. | `string` | `"kind"` | no |
| pod\_subnet | Pod CIDR. The CNI installed in 20-platform must use the same range. | `string` | `"10.244.0.0/16"` | no |
| port\_mappings | Host ports forwarded to control-plane node ports, keyed by a name (e.g. http, https). container\_port is the NodePort the gateway listens on. | <pre>map(object({<br/>    container_port = number<br/>    host_port      = number<br/>    listen_address = optional(string, "127.0.0.1")<br/>    protocol       = optional(string, "TCP")<br/>  }))</pre> | `{}` | no |
| service\_subnet | Service CIDR. | `string` | `"10.96.0.0/12"` | no |
| worker\_count | Number of worker nodes (in addition to the single control-plane node). | `number` | `2` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| client\_certificate | PEM client certificate (cluster-admin) for the local cluster. |
| client\_key | PEM client key (cluster-admin) for the local cluster. Local state only; never used outside kind. |
| cluster\_ca\_certificate | PEM CA certificate of the API server. |
| cluster\_name | Name of the kind cluster. |
| context\_name | kubectl context name for the cluster. |
| endpoint | Kubernetes API server endpoint, for the helm/kubernetes providers in 20-platform and 30-apps. |
| kubeconfig\_path | Kubeconfig file the context was merged into. |
| kubernetes\_version | Kubernetes version of the nodes (from the pinned node image). |
| network\_name | Docker network shared by the nodes and the registry. |
| registry\_host | Registry address used by the host and in image references (e.g. localhost:5001/notes-api:<sha>). |
| registry\_in\_cluster | Registry address as seen from inside the kind network. |
<!-- END_TF_DOCS -->
