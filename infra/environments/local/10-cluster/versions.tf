terraform {
  required_version = ">= 1.16.0, < 2.0.0"

  # Local environment: local state (ADR-0008). 20-platform reads it via terraform_remote_state.
  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "= 0.11.0" # embeds kind v0.31.0 — node images must come from that release
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "= 4.6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "= 2.9.1"
    }
  }
}
