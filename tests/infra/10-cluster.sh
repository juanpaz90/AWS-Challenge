#!/usr/bin/env bash
# Checks for the local/10-cluster stack (Phase 5, story S2).
#   tests/infra/10-cluster.sh up    → after apply: nodes, version, port mappings, registry mirror
#   tests/infra/10-cluster.sh down  → after destroy: no containers, network or context left
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")/../../infra/environments/local/10-cluster" && pwd)"
CLUSTER="${CLUSTER:-notes-local}"
CONTEXT="kind-${CLUSTER}"
REGISTRY_CONTAINER="${REGISTRY_CONTAINER:-kind-registry}"
NETWORK="${NETWORK:-kind}"

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*" >&2; exit 1; }

check_up() {
  local expected_version nodes
  expected_version="$(terraform -chdir="$STACK_DIR" output -raw kubernetes_version)"

  nodes="$(kubectl --context "$CONTEXT" get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$nodes" == 3 ]] || fail "expected 3 nodes, got $nodes"
  pass "3 nodes (1 control plane + 2 workers)"

  kubectl --context "$CONTEXT" get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' \
    | sort -u | grep -qx "$expected_version" || fail "kubelet version is not $expected_version"
  pass "all kubelets run $expected_version"

  if kubectl --context "$CONTEXT" -n kube-system get ds kindnet >/dev/null 2>&1; then fail "kindnet is installed"; fi
  pass "default CNI disabled (nodes stay NotReady until Calico in 20-platform)"

  local ports
  ports="$(docker port "${CLUSTER}-control-plane")"
  grep -q '^30080/tcp -> 127.0.0.1:80$' <<<"$ports" || fail "30080 -> 127.0.0.1:80 mapping missing: $ports"
  grep -q '^30443/tcp -> 127.0.0.1:443$' <<<"$ports" || fail "30443 -> 127.0.0.1:443 mapping missing: $ports"
  pass "host 80/443 mapped to NodePorts 30080/30443 on 127.0.0.1"

  curl -fsS http://localhost:5001/v2/ >/dev/null || fail "registry not reachable on localhost:5001"
  pass "registry reachable from the host on localhost:5001"

  # Prove the containerd mirror: push a tiny image from the host, pull it inside a worker.
  local probe="localhost:5001/registry-probe:${RANDOM}"
  docker tag "$(docker inspect -f '{{.Config.Image}}' "$REGISTRY_CONTAINER")" "$probe"
  docker push -q "$probe" >/dev/null
  docker exec "${CLUSTER}-worker" crictl pull "$probe" >/dev/null || fail "node could not pull $probe via the mirror"
  docker exec "${CLUSTER}-worker" crictl rmi "$probe" >/dev/null 2>&1 || true
  docker rmi "$probe" >/dev/null
  pass "nodes pull localhost:5001/* through the containerd mirror"
}

check_down() {
  local leftovers
  leftovers="$(docker ps -a --format '{{.Names}}' | grep -E "^(${CLUSTER}-|${REGISTRY_CONTAINER}$)" || true)"
  [[ -z "$leftovers" ]] || fail "containers left: $leftovers"
  pass "no node or registry containers left"

  if docker network inspect "$NETWORK" >/dev/null 2>&1; then fail "docker network '$NETWORK' still exists"; fi
  pass "docker network '$NETWORK' removed"

  if kubectl config get-contexts -o name 2>/dev/null | grep -qx "$CONTEXT"; then fail "kube context $CONTEXT still exists"; fi
  pass "kube context $CONTEXT removed"

  [[ ! -e "$STACK_DIR/.generated" ]] || fail "generated node config left in $STACK_DIR/.generated"
  pass "generated node config removed"
}

case "${1:-}" in
  up) check_up ;;
  down) check_down ;;
  *) echo "usage: $0 up|down" >&2; exit 2 ;;
esac
