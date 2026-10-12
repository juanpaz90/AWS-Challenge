# Cluster connection from 10-cluster; platform facts (gateway label, ...) from 20-platform.
data "terraform_remote_state" "cluster" {
  backend = "local"
  config = {
    path = "${path.module}/../10-cluster/terraform.tfstate"
  }
}

data "terraform_remote_state" "platform" {
  backend = "local"
  config = {
    path = "${path.module}/../20-platform/terraform.tfstate"
  }
}

locals {
  cluster  = data.terraform_remote_state.cluster.outputs
  platform = data.terraform_remote_state.platform.outputs
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
