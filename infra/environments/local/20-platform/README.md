# Stack: local/20-platform

Second of the three local stacks ([ADR-0002](../../../../docs/adr/0002-three-stack-terraform-layout.md)). Installs the [`platform-addons`](../../../modules/platform-addons) module on the cluster created by `10-cluster`, whose connection details (endpoint, certificates, pod CIDR, gateway NodePorts, registry host) are read through `terraform_remote_state`.

```bash
task platform:up        # terraform init + apply (add `-- -auto-approve` to skip the prompt)
task platform:check     # nodes Ready, releases, PSA, metrics, TLS, gateway, Grafana, logs
task platform:down      # terraform destroy
```

After it is applied:

- **Grafana:** <https://grafana.localtest.me> — user `admin`, password generated in-cluster:
  `kubectl --context kind-notes-local -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d`
- **Trusting the local CA** (optional, avoids `curl -k`):
  `kubectl --context kind-notes-local -n cert-manager get secret local-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > local-ca.crt`

Chart versions are pinned in `terraform.tfvars`; check each project's status before bumping.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.16.0, < 2.0.0 |
| helm | = 3.3.0 |
| kubernetes | = 3.3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| terraform | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| platform | ../../../modules/platform-addons | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_remote_state.cluster](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| chart\_versions | Exact chart versions for every platform add-on. | <pre>object({<br/>    calico                = string<br/>    cert_manager          = string<br/>    envoy_gateway         = string<br/>    metrics_server        = string<br/>    cloudnative_pg        = string<br/>    kube_prometheus_stack = string<br/>    loki                  = string<br/>    alloy                 = string<br/>  })</pre> | n/a | yes |
| domain | Base domain served by the gateway; *.localtest.me resolves to 127.0.0.1. | `string` | n/a | yes |
| labels | Labels added to platform namespaces. | `map(string)` | `{}` | no |
| observability\_enabled | Install Prometheus, Grafana, Loki and Alloy (set false on low-memory machines). | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_issuer | ClusterIssuer for application certificates. |
| context\_name | kubectl context of the cluster this stack targets. |
| gateway | Shared Gateway reference for application HTTPRoutes. |
| grafana\_url | Grafana through the gateway. |
| namespaces | Platform namespaces and their Pod Security enforce level. |
<!-- END_TF_DOCS -->
