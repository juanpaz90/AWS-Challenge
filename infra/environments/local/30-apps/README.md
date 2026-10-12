# Stack: local/30-apps

Third local stack ([ADR-0002](../../../../docs/adr/0002-three-stack-terraform-layout.md)): the `notes` namespace, PostgreSQL (CloudNativePG, 1 instance on `local-path`) and the Notes API, via the [`notes-app`](../../../modules/notes-app) module. It reads the cluster connection from `10-cluster` and the gateway facts from `20-platform`.

```bash
task apps:up      # build + push the image, then terraform apply with its tag and registry digest
task apps:check   # database Ready/private, exact image running, CRUD through https://api.localtest.me
task apps:down    # terraform destroy

task up           # all three stacks, in order (add `-- -auto-approve`)
task down         # all three stacks, in reverse order
```

`image_tag` has no default on purpose: the task passes the git SHA of the image it just pushed and the digest the registry reports for it. To demo a configuration change: `task apps:up -- -var app_message="hello v2"`.

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
| notes\_app | ../../../modules/notes-app | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_remote_state.cluster](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |
| [terraform_remote_state.platform](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cnpg\_cluster\_chart\_version | Version of the CloudNativePG `cluster` chart. | `string` | n/a | yes |
| database\_storage\_size | PVC size of each PostgreSQL instance. | `string` | n/a | yes |
| image\_tag | Notes API image tag (git SHA). Set by `task apps:up` after building and pushing the image; there is no default on purpose. | `string` | n/a | yes |
| postgres\_image | PostgreSQL operand image, pinned by digest. | `string` | n/a | yes |
| app\_message | Optional override of the API's message (GET /), used to demo a configuration change and rolling update. | `string` | `null` | no |
| image\_digest | Digest of the pushed image (sha256:...). When set the release pins it, so a rebuilt '-dirty' tag can never be served stale. | `string` | `""` | no |
| labels | Labels added to the notes namespace. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| api\_release | Notes API release and the exact image it runs. |
| api\_url | Public URL of the Notes API through the gateway. |
| database | Database cluster, credentials Secret and read-write Service (all in-cluster only). |
| namespace | Namespace of the API and database. |
<!-- END_TF_DOCS -->
