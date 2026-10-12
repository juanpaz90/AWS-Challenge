terraform {
  required_version = ">= 1.10.0"

  # Lower bounds only: exact versions are pinned by the root stacks and their lock files.
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.3.0"
    }
  }
}
