# Cluster connection comes from the 10-cluster stack's state (ADR-0002), never from a
# hand-maintained kubeconfig, so this stack always targets the cluster 10-cluster created.
data "terraform_remote_state" "cluster" {
  backend = "local"
  config = {
    path = "${path.module}/../10-cluster/terraform.tfstate"
  }
}

locals {
  cluster = data.terraform_remote_state.cluster.outputs
}

provider "kubernetes" {
  host                   = local.cluster.endpoint
  cluster_ca_certificate = local.cluster.cluster_ca_certificate
  client_certificate     = local.cluster.client_certificate
  client_key             = local.cluster.client_key
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster.endpoint
    cluster_ca_certificate = local.cluster.cluster_ca_certificate
    client_certificate     = local.cluster.client_certificate
    client_key             = local.cluster.client_key
  }
}
