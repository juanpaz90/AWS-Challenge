#!/usr/bin/env bash
# Phase 9 — local validation suite (Functionality criterion; stories S4, S5, S6).
# Proves every core requirement against the running environment with scripted checks.
#
#   task test                      # all 10 checks (~15 min; check 6 runs a k6 load test)
#   CHECKS="1 2 3" task test       # a subset
#
# Checks 5–9 change the live environment (HPA, Terraform apply, helm rollback, node drain)
# and restore it; check 10 runs last and proves nothing drifted.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONTEXT="${CONTEXT:-kind-notes-local}"
NS="${NS:-notes}"
API="${API:-https://api.localtest.me}"
CHECKS="${CHECKS:-1 2 3 4 5 6 7 8 9 10}"
LOAD_VUS="${LOAD_VUS:-20}"
LOAD_DURATION="${LOAD_DURATION:-4m}"

k() { kubectl --context "$CONTEXT" "$@"; }
h() { helm --kube-context "$CONTEXT" "$@"; }

WORK="$(mktemp -d)"
MONITOR_PID=""
cleanup() {
  [[ -n "$MONITOR_PID" ]] && kill "$MONITOR_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

step() { echo; echo "=== Check $1: $2"; }
pass() { echo "PASS  $*"; }
info() { echo "INFO  $*"; }
fail() { echo "FAIL  $*" >&2; exit 1; }
want() { [[ " $CHECKS " == *" $1 "* ]]; }

CA="$WORK/local-ca.crt"
k -n cert-manager get secret local-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CA"
api() { curl -fsS --cacert "$CA" "$@"; }

wait_api_ready() {
  for _ in $(seq 1 90); do
    api -o /dev/null "$API/readyz" 2>/dev/null && return 0
    sleep 2
  done
  fail "API not ready through the gateway"
}

# Background availability probe: one request every ~100 ms; records HTTP status codes.
monitor_start() {
  : >"$WORK/monitor.log"
  (
    while :; do
      # "<epoch> <http_code> <curl_exit> <seconds> <error>" per request
      out="$(curl -s -o /dev/null -w '%{http_code} %{exitcode} %{time_total} %{errormsg}' --max-time 5 --cacert "$CA" "$API/notes?limit=1" 2>/dev/null)"
      echo "$(date +%s) ${out}" >>"$WORK/monitor.log"
      sleep 0.1
    done
  ) &
  MONITOR_PID=$!
  disown "$MONITOR_PID" # no "Terminated" job notice when it is stopped
}
monitor_stop() { # prints "<total> <failures>"
  kill "$MONITOR_PID" 2>/dev/null || true
  while kill -0 "$MONITOR_PID" 2>/dev/null; do sleep 0.1; done
  MONITOR_PID=""
  local total failures
  total="$(wc -l <"$WORK/monitor.log" | tr -d ' ')"
  failures="$(awk '$2 != "200"' "$WORK/monitor.log" | wc -l | tr -d ' ')"
  if [[ "$failures" != 0 ]]; then
    { echo "      failed requests (epoch http_code curl_exit seconds error):"
      awk '$2 != "200" {print "        " $0}' "$WORK/monitor.log" | head -20; } >&2
  fi
  echo "$total $failures"
}

message() { api "$API/" | jq -r .message; }

# Throwaway pod that resolves a host and tries a TCP connection. Uses the API image (it has
# Python) under the restricted Pod Security profile, without any notes-api labels.
probe_pod() { # namespace host port -> prints the pod's verdict line
  local ns="$1" host="$2" port="$3" name="netpol-probe-$RANDOM" image overrides
  image="$(k -n "$NS" get deploy notes-api -o jsonpath='{.spec.template.spec.containers[0].image}')"
  overrides="$(jq -n --arg img "$image" --arg host "$host" --arg port "$port" --arg name "$name" '{
    spec: {
      securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: "RuntimeDefault"}},
      automountServiceAccountToken: false,
      containers: [{
        name: $name, image: $img,
        command: ["python", "-c", "import socket,sys\nh,p=sys.argv[1],int(sys.argv[2])\ntry:\n ip=socket.gethostbyname(h)\nexcept Exception as e:\n print(\"DNS_FAIL\",e);sys.exit()\ntry:\n socket.create_connection((ip,p),timeout=4).close();print(\"CONNECTED\",ip)\nexcept Exception as e:\n print(\"BLOCKED\",ip,type(e).__name__)", $host, $port],
        securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
      }]
    }}')"
  k -n "$ns" run "$name" --image="$image" --restart=Never --labels="app.kubernetes.io/name=netpol-probe" \
    --overrides="$overrides" >/dev/null
  k -n "$ns" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$name" --timeout=120s >/dev/null \
    || { k -n "$ns" logs "$name" >&2 || true; k -n "$ns" delete pod "$name" --wait=false >/dev/null; fail "probe pod $name did not complete"; }
  k -n "$ns" logs "$name"
  k -n "$ns" delete pod "$name" --wait=false >/dev/null
}

wait_api_ready

# --- 1. API reachable from outside ------------------------------------------------------------
if want 1; then
  step 1 "API reachable from outside through the gateway"
  headers="$(curl -fsS -D - -o "$WORK/body.json" --cacert "$CA" "$API/")"
  grep -qi '^HTTP/[0-9.]* 200' <<<"$headers" || fail "GET $API/ not 200"
  pod="$(grep -i '^x-pod-name:' <<<"$headers" | awk '{print $2}' | tr -d '\r')"
  pass "GET $API/ → 200 from pod $pod, TLS verified against the local CA ($(jq -c . "$WORK/body.json"))"
fi

# --- 2. DB not reachable from outside ---------------------------------------------------------
if want 2; then
  step 2 "Database not reachable from outside the cluster"
  external="$(k get svc -A -o json | jq -r '.items[] | select(.spec.type != "ClusterIP") | "\(.metadata.namespace)/\(.metadata.name)"')"
  if grep -v '^gateway/envoy-gateway-' <<<"$external" | grep -q .; then
    fail "unexpected externally exposed Services: $(xargs <<<"$external")"
  fi
  pass "the only non-ClusterIP Service in the cluster is the gateway's Envoy ($(xargs <<<"$external"))"

  routes="$(k get httproute -A -o json | jq -r '[.items[].spec.rules[].backendRefs[]?.name] | unique | join(",")')"
  [[ "$routes" != *notes-db* ]] || fail "an HTTPRoute points at the database: $routes"
  pass "no gateway route targets the database (route backends: $routes)"

  for node in $(k get nodes -o name | cut -d/ -f2); do
    if docker port "$node" 2>/dev/null | grep -q '^5432/'; then fail "node $node publishes 5432 to the host"; fi
  done
  pass "no kind node publishes port 5432 to the host"

  if curl -s --connect-timeout 2 -o /dev/null "telnet://127.0.0.1:5432" 2>/dev/null; then
    info "something on this machine listens on 127.0.0.1:5432 — not the cluster database (no mapping exists)"
  else
    pass "connection to 127.0.0.1:5432 from the host fails"
  fi
fi

# --- 3. Only the API reaches the DB -----------------------------------------------------------
if want 3; then
  step 3 "Only the API can reach the database (NetworkPolicy)"
  verdict="$(probe_pod "$NS" notes-db-rw 5432)"
  [[ "$verdict" == BLOCKED* ]] || fail "unlabelled pod in $NS reached the database: $verdict"
  pass "throwaway pod in '$NS' (no API labels): DNS works, 5432 blocked → $verdict"

  verdict="$(probe_pod default notes-db-rw.$NS.svc.cluster.local 5432)"
  [[ "$verdict" == BLOCKED* || "$verdict" == DNS_FAIL* ]] || fail "pod in 'default' reached the database: $verdict"
  pass "throwaway pod in 'default' namespace: 5432 blocked → $verdict"

  verdict="$(k -n "$NS" exec deploy/notes-api -c api -- python -c \
    "import socket;ip=socket.gethostbyname('notes-db-rw');socket.create_connection((ip,5432),timeout=4).close();print('CONNECTED',ip)")"
  [[ "$verdict" == CONNECTED* ]] || fail "API pod cannot reach the database: $verdict"
  pass "positive control: API pod → database 5432 allowed → $verdict"
fi

# --- 4. Persistence ---------------------------------------------------------------------------
if want 4; then
  step 4 "Data survives deleting the database pod"
  marker="persist-$(date +%s)-$RANDOM"
  id="$(api -X POST "$API/notes" -H 'Content-Type: application/json' -d "{\"title\":\"persistence\",\"content\":\"$marker\"}" | jq -r .id)"
  pod="$(k -n "$NS" get pod -l cnpg.io/cluster=notes-db,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')"
  old_uid="$(k -n "$NS" get pod "$pod" -o jsonpath='{.metadata.uid}')"
  k -n "$NS" delete pod "$pod" --wait=true >/dev/null
  for _ in $(seq 1 120); do
    uid="$(k -n "$NS" get pod "$pod" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
    ready="$(k -n "$NS" get pod "$pod" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
    [[ -n "$uid" && "$uid" != "$old_uid" && "$ready" == true ]] && break
    sleep 2
  done
  [[ "$uid" != "$old_uid" && "$ready" == true ]] || fail "database pod $pod was not recreated and Ready"
  wait_api_ready
  [[ "$(api "$API/notes/$id" | jq -r .content)" == "$marker" ]] || fail "note $id lost after the database pod was deleted"
  pass "note $id written → pod $pod deleted and recreated (new UID, same PVC) → note still there"
fi

# --- 5. Multiple replicas ---------------------------------------------------------------------
if want 5; then
  step 5 "Multiple replicas serve traffic"
  original_min="$(k -n "$NS" get hpa notes-api -o jsonpath='{.spec.minReplicas}')"
  k -n "$NS" patch hpa notes-api --type merge -p '{"spec":{"minReplicas":3}}' >/dev/null
  for _ in $(seq 1 90); do
    [[ "$(k -n "$NS" get deploy notes-api -o jsonpath='{.status.readyReplicas}')" == 3 ]] && break
    sleep 2
  done
  [[ "$(k -n "$NS" get deploy notes-api -o jsonpath='{.status.readyReplicas}')" == 3 ]] || fail "did not reach 3 ready replicas"
  pods="$(for _ in $(seq 1 60); do curl -fsS -o /dev/null -D - --cacert "$CA" "$API/" | grep -i '^x-pod-name:' | awk '{print $2}' | tr -d '\r'; done | sort | uniq -c)"
  distinct="$(wc -l <<<"$pods" | tr -d ' ')"
  k -n "$NS" patch hpa notes-api --type merge -p "{\"spec\":{\"minReplicas\":$original_min}}" >/dev/null
  [[ "$distinct" == 3 ]] || fail "60 requests hit $distinct pods, expected 3: $(xargs <<<"$pods")"
  pass "scaled to 3; 60 requests were served by 3 different pods ($(awk '{printf "%s×%s ", $2, $1}' <<<"$pods"))"
  info "HPA minReplicas restored to $original_min"
fi

# --- 6. Autoscaling ---------------------------------------------------------------------------
if want 6; then
  step 6 "HPA scales out under load and back in afterwards"
  command -v k6 >/dev/null || fail "k6 is not installed"
  min="$(k -n "$NS" get hpa notes-api -o jsonpath='{.spec.minReplicas}')"
  for _ in $(seq 1 120); do
    [[ "$(k -n "$NS" get hpa notes-api -o jsonpath='{.status.currentReplicas}')" == "$min" ]] && break
    sleep 3
  done
  info "baseline: $min replicas; starting k6 (${LOAD_VUS} VUs for ${LOAD_DURATION})"
  BASE_URL="$API" VUS="$LOAD_VUS" DURATION="$LOAD_DURATION" k6 run --quiet --summary-export "$WORK/k6.json" \
    "$ROOT/tests/load/notes-api.js" >"$WORK/k6.log" 2>&1 &
  k6_pid=$!
  peak="$min"
  for _ in $(seq 1 80); do
    desired="$(k -n "$NS" get hpa notes-api -o jsonpath='{.status.desiredReplicas}')"
    (( desired > peak )) && peak="$desired"
    (( peak > min )) && break
    sleep 3
  done
  (( peak > min )) || { kill "$k6_pid" 2>/dev/null || true; fail "HPA did not scale out under load (stayed at $min)"; }
  pass "scale-out: HPA desired replicas went from $min to $peak under load"
  wait "$k6_pid" || true
  peak="$(k -n "$NS" get hpa notes-api -o jsonpath='{.status.currentReplicas}')"
  if [[ -f "$WORK/k6.json" ]]; then
    info "k6: $(jq -r '"\(.metrics.http_reqs.count) requests, failed \((.metrics.http_req_failed.value // .metrics.http_req_failed.rate) * 100 | floor)%, p95 \(.metrics.http_req_duration["p(95)"] | floor) ms"' "$WORK/k6.json")"
  fi
  for _ in $(seq 1 150); do
    [[ "$(k -n "$NS" get hpa notes-api -o jsonpath='{.status.currentReplicas}')" == "$min" ]] && break
    sleep 4
  done
  [[ "$(k -n "$NS" get hpa notes-api -o jsonpath='{.status.currentReplicas}')" == "$min" ]] || fail "HPA did not scale back in to $min"
  pass "scale-in: back to $min replicas after the load stopped"
fi

# --- 7. Basic modification takes effect -------------------------------------------------------
if want 7; then
  step 7 "A configuration change rolls out with zero downtime"
  original_message="$(message)"
  new_message="e2e change $(date +%H%M%S)"
  monitor_start
  (cd "$ROOT" && task apps:up -- -auto-approve -no-color -var "app_message=$new_message" >"$WORK/apply7.log" 2>&1) \
    || { monitor_stop >/dev/null; tail -20 "$WORK/apply7.log" >&2; fail "terraform apply failed"; }
  k -n "$NS" rollout status deploy/notes-api --timeout=300s >/dev/null
  sleep 3
  read -r total failures <<<"$(monitor_stop)"
  [[ "$(message)" == "$new_message" ]] || fail "message is '$(message)', expected '$new_message'"
  [[ "$failures" == 0 ]] || fail "$failures of $total requests failed during the rollout"
  pass "Terraform apply changed the message '$original_message' → '$new_message'; rolling update served $total requests with 0 errors"
fi

# --- 8. Rollback ------------------------------------------------------------------------------
if want 8; then
  step 8 "helm rollback restores the previous revision"
  want 7 || fail "check 8 rolls back the change made by check 7; run them together"
  before="$(message)"
  rev_before="$(h -n "$NS" history notes-api -o json | jq -r 'last.revision')"
  monitor_start
  h -n "$NS" rollback notes-api --wait --timeout 5m >/dev/null
  k -n "$NS" rollout status deploy/notes-api --timeout=300s >/dev/null
  sleep 3
  read -r total failures <<<"$(monitor_stop)"
  after="$(message)"
  [[ "$after" != "$before" ]] || fail "rollback did not change the message ('$after')"
  [[ "$failures" == 0 ]] || fail "$failures of $total requests failed during the rollback"
  pass "rollback from revision $rev_before: message '$before' → '$after', $total requests with 0 errors"

  # Bring Terraform's view back in line with the cluster (state still holds the changed value).
  (cd "$ROOT" && task apps:up -- -auto-approve -no-color >"$WORK/apply8.log" 2>&1) \
    || { tail -20 "$WORK/apply8.log" >&2; fail "terraform reconcile after rollback failed"; }
  [[ "$(message)" == "$after" ]] || fail "after Terraform reconcile the message is '$(message)'"
  pass "Terraform reconciled to the configured values (message '$(message)')"
fi

# --- 9. Resilience: drain a worker ------------------------------------------------------------
if want 9; then
  step 9 "Draining a worker keeps the API available (PDB + spread)"
  db_node="$(k -n "$NS" get pod -l cnpg.io/cluster=notes-db,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].spec.nodeName}')"
  # The database volume is local-path, i.e. bound to one node: draining that node would stop
  # PostgreSQL until it is uncordoned (EBS + 3 instances remove this on AWS). Drain the other.
  node="$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o name | cut -d/ -f2 | grep -vx "$db_node" | head -1)"
  [[ -n "$node" ]] || fail "no worker without the database to drain"
  count_api() { k -n "$NS" get pods -l app.kubernetes.io/name=notes-api,app.kubernetes.io/component=api --field-selector "spec.nodeName=$node,status.phase=Running" -o name | wc -l | tr -d ' '; }
  count_envoy() { k -n gateway get pods -l gateway.envoyproxy.io/owning-gateway-name=platform --field-selector "spec.nodeName=$node,status.phase=Running" -o name | wc -l | tr -d ' '; }
  # Pods are not rebalanced after an uncordon, so a previous drain can leave this node empty
  # and the check would pass without disrupting anything. Respread first (zero-downtime
  # rollouts, see checks 7–8) and refuse to report a vacuous pass.
  for attempt in 1 2 3; do
    [[ "$(count_api)" -ge 1 && "$(count_envoy)" -ge 1 ]] && break
    info "respreading API and Envoy pods onto both workers (attempt $attempt)"
    k -n "$NS" rollout restart deploy/notes-api >/dev/null
    k -n gateway rollout restart deploy -l gateway.envoyproxy.io/owning-gateway-name=platform >/dev/null
    k -n "$NS" rollout status deploy/notes-api --timeout=300s >/dev/null
    k -n gateway rollout status deploy -l gateway.envoyproxy.io/owning-gateway-name=platform --timeout=300s >/dev/null
    sleep 5
  done
  api_pods="$(count_api)"; envoy_pods="$(count_envoy)"
  [[ "$api_pods" -ge 1 && "$envoy_pods" -ge 1 ]] || fail "inconclusive: $node hosts $api_pods API and $envoy_pods Envoy pods, so a drain would not test anything"
  info "draining $node (API pods: $api_pods, Envoy pods: $envoy_pods; database on $db_node)"
  monitor_start
  k drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=300s >"$WORK/drain.log" 2>&1 \
    || { k uncordon "$node" >/dev/null; monitor_stop >/dev/null; tail -20 "$WORK/drain.log" >&2; fail "drain failed"; }
  k -n "$NS" rollout status deploy/notes-api --timeout=300s >/dev/null
  sleep 5
  read -r total failures <<<"$(monitor_stop)"
  left="$(k -n "$NS" get pods -l app.kubernetes.io/name=notes-api,app.kubernetes.io/component=api --field-selector "spec.nodeName=$node" -o name | wc -l | tr -d ' ')"
  k uncordon "$node" >/dev/null
  [[ "$left" == 0 ]] || fail "$left API pods still on drained node $node"
  [[ "$failures" == 0 ]] || fail "$failures of $total requests failed during the drain"
  pass "drained $node: API pods moved, $total requests during the drain with 0 errors; node uncordoned"
fi

# --- 10. Idempotency --------------------------------------------------------------------------
if want 10; then
  step 10 "Re-planning every stack shows no changes"
  export DOCKER_HOST="${DOCKER_HOST:-$(docker context inspect | jq -r '.[0].Endpoints.docker.Host')}"
  tag="$(git -C "$ROOT" rev-parse --short HEAD)"
  [[ -z "$(git -C "$ROOT" status --porcelain -- app)" ]] || tag="${tag}-dirty"
  digest="$(curl -fsSI -H 'Accept: application/vnd.oci.image.index.v1+json' -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    "http://localhost:5001/v2/notes-api/manifests/$tag" | awk 'tolower($1)=="docker-content-digest:" {print $2}' | tr -d '\r')"
  for stack in 10-cluster 20-platform 30-apps; do
    dir="$ROOT/infra/environments/local/$stack"
    args=()
    [[ "$stack" == 30-apps ]] && args=(-var "image_tag=$tag" -var "image_digest=$digest")
    set +e
    terraform -chdir="$dir" plan -input=false -no-color -detailed-exitcode -lock=false "${args[@]+"${args[@]}"}" >"$WORK/plan-$stack.log" 2>&1
    rc=$?
    set -e
    case "$rc" in
      0) pass "$stack: no changes" ;;
      2) grep -E '^  # ' "$WORK/plan-$stack.log" >&2; fail "$stack: plan shows changes" ;;
      *) tail -20 "$WORK/plan-$stack.log" >&2; fail "$stack: plan failed" ;;
    esac
  done
fi

echo
echo "All selected checks passed: $CHECKS"
