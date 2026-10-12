#!/usr/bin/env bash
# Checks for the local/30-apps stack (Phase 8, story S5): database + Notes API through the gateway.
set -euo pipefail

CONTEXT="${CONTEXT:-kind-notes-local}"
NS="${NS:-notes}"
API="${API:-https://api.localtest.me}"
STACK_DIR="$(cd "$(dirname "$0")/../../infra/environments/local/30-apps" && pwd)"
k() { kubectl --context "$CONTEXT" "$@"; }

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*" >&2; exit 1; }

# 1. Namespace guardrails
[[ "$(k get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')" == restricted ]] \
  || fail "namespace $NS is not PSA restricted"
pass "namespace $NS enforces Pod Security restricted"

# 2. Database: Ready, persistent, private, operator-generated credentials only
k -n "$NS" wait --for=condition=Ready cluster.postgresql.cnpg.io/notes-db --timeout=300s >/dev/null || fail "CNPG cluster not Ready"
pvc="$(k -n "$NS" get pvc -l cnpg.io/cluster=notes-db -o jsonpath='{range .items[*]}{.status.phase}/{.spec.storageClassName}{"\n"}{end}')"
grep -qx 'Bound/standard' <<<"$pvc" || fail "database PVC not Bound on 'standard': $pvc"
pass "CNPG cluster notes-db Ready with a Bound PVC (local-path)"

exposed="$(k -n "$NS" get svc -o json | jq -r '.items[] | select(.spec.type != "ClusterIP") | .metadata.name')"
[[ -z "$exposed" ]] || fail "non-ClusterIP services in $NS: $exposed"
pass "every Service in $NS is ClusterIP (database not exposed outside the cluster)"

k -n "$NS" get secret notes-db-app >/dev/null || fail "Secret notes-db-app missing"
if k -n "$NS" get secret notes-db-superuser >/dev/null 2>&1; then fail "superuser Secret exists"; fi
if grep -q 'password' "$STACK_DIR/terraform.tfstate" 2>/dev/null && \
   jq -e '[.resources[].instances[].attributes | tostring | test("\"password\"\\s*:\\s*\"[^\"]+\"")] | any' "$STACK_DIR/terraform.tfstate" >/dev/null; then
  fail "a password value appears in the 30-apps Terraform state"
fi
pass "credentials only in the CNPG Secret (no superuser Secret, no password in Terraform state)"

# 3. Notes API workload
k -n "$NS" rollout status deployment/notes-api --timeout=300s >/dev/null || fail "notes-api not rolled out"
ready="$(k -n "$NS" get deployment notes-api -o jsonpath='{.status.readyReplicas}')"
[[ "$ready" -ge 2 ]] || fail "only $ready ready replicas"
k -n "$NS" get hpa notes-api >/dev/null && k -n "$NS" get pdb notes-api >/dev/null || fail "HPA or PDB missing"
pass "notes-api: $ready ready replicas, HPA and PDB present"

image="$(k -n "$NS" get deployment notes-api -o jsonpath='{.spec.template.spec.containers[0].image}')"
expected="$(terraform -chdir="$STACK_DIR" output -json api_release | jq -r .image)"
[[ "$image" == "$expected" ]] || fail "running image $image != $expected"
[[ "$image" == *@sha256:* ]] || fail "image is not pinned by digest: $image"
pass "running the exact pushed image ($image)"

# 4. Through the gateway, TLS verified against the local CA
ca="$(mktemp)"; trap 'rm -f "$ca"' EXIT
k -n cert-manager get secret local-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >"$ca"
info=""
for _ in $(seq 1 30); do
  info="$(curl -fsS --cacert "$ca" "$API/" 2>/dev/null || true)"
  [[ -n "$info" ]] && break
  sleep 3
done
jq -e '.service == "notes-api" and (.pod | startswith("notes-api-"))' <<<"$info" >/dev/null || fail "GET $API/ -> '$info'"
pass "GET $API/ → $(jq -c . <<<"$info")"

marker="phase8-$(date +%s)-$RANDOM"
id="$(curl -fsS --cacert "$ca" -X POST "$API/notes" -H 'Content-Type: application/json' \
  -d "{\"title\":\"phase 8\",\"content\":\"$marker\"}" | jq -r .id)"
[[ "$(curl -fsS --cacert "$ca" "$API/notes/$id" | jq -r .content)" == "$marker" ]] || fail "note $id not readable"
pass "create + read a note through the gateway (id $id) — migrations ran, API ↔ DB works"

[[ "$(curl -sS -o /dev/null -w '%{http_code}' "http://api.localtest.me/")" == 301 ]] || fail "HTTP not redirected"
pass "HTTP → HTTPS redirect"

echo "All 30-apps checks passed."
