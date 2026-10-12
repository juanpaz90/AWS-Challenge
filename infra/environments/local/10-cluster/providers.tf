# The docker provider does not read Docker CLI contexts (e.g. Colima), so the socket comes
# from var.docker_host or DOCKER_HOST; `task cluster:up` sets DOCKER_HOST automatically.
provider "docker" {
  host = var.docker_host
}

provider "kind" {}

provider "local" {}
