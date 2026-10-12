terraform {
  required_version = ">= 1.10.0"

  # Lower bounds only: exact versions are pinned by the root stacks and their lock files.
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = ">= 0.11.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 4.6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.9.0"
    }
  }
}
