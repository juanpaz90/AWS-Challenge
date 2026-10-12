#!/usr/bin/env bash
# Phase 10 checks against the running environment (story S7):
#   1. rules loaded in Prometheus and healthy; dashboard + datasources loaded in Grafana
#   2. a k6 load test is visible through the dashboard's own panel queries
#   3. logs are searchable in Loki by namespace, pod and JSON fields
#   4. an induced failure (API scaled to 0) fires NotesApiDown in Alertmanager, then resolves
# Check 4 causes a short, deliberate outage of the API.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONTEXT="${CONTEXT:-kind-notes-local}"
NS="${NS:-notes}"
API="${API:-https://api.localtest.me}"
GRAFANA="${GRAFANA:-https://grafana.localtest.me}"
LOAD_DURATION="${LOAD_DURATION:-90s}"
DASHBOARD="$ROOT/observability/dashboards/notes-api.json"

k() { kubectl --context "$CONTEXT" "$@"; }
pass() { echo "PASS  $*"; }
info() { echo "INFO  $*"; }
fail() { echo "FAIL  $*" >&2; exit 1; }
urlencode() { python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

PROM=/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1
AM=/api/v1/namespaces/monitoring/services/kube-prometheus-stack-alertmanager:9093/proxy/api/v2
LOKI=/api/v1/namespaces/monitoring/services/loki:3100/proxy/loki/api/v1
prom_query() { k get --raw "$PROM/query?query=$(urlencode "$1")"; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
CA="$WORK/ca.crt"
k -n cert-manager get secret local-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >"$CA"
GRAFANA_PASSWORD="$(k -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
grafana() { curl -fsS --cacert "$CA" -u "admin:$GRAFANA_PASSWORD" "$GRAFANA$1"; }

# --- 1. Rules and dashboard loaded -----------------------------------------------------------
echo "=== 1. Rules, dashboard and datasources loaded"
groups="$(k get --raw "$PROM/rules" | jq -c '[.data.groups[] | select(.name | startswith("notes-api")) | {name, rules: (.rules | length), unhealthy: ([.rules[] | select(.health != "ok")] | length)}]')"
jq -e 'length == 2 and all(.[]; .unhealthy == 0)' <<<"$groups" >/dev/null || fail "notes-api rule groups missing or unhealthy: $groups"
pass "Prometheus loaded the notes-api rule groups, all rules healthy: $groups"

title="$(grafana /api/dashboards/uid/notes-api | jq -r .dashboard.title)"
[[ "$title" == "Notes API" ]] || fail "dashboard notes-api not found in Grafana"
for ds in prometheus loki; do
  [[ "$(grafana "/api/datasources/uid/$ds/health" | jq -r .status)" == OK ]] || fail "Grafana datasource $ds unhealthy"
done
pass "Grafana serves the 'Notes API' dashboard (uid notes-api); Prometheus and Loki datasources healthy"

# --- 2. Load test visible on the dashboard -----------------------------------------------------
echo "=== 2. Load test visible on the dashboard"
command -v k6 >/dev/null || fail "k6 is not installed"
info "running k6 for $LOAD_DURATION"
BASE_URL="$API" DURATION="$LOAD_DURATION" VUS=10 k6 run --quiet "$ROOT/tests/load/notes-api.js" >"$WORK/k6.log" 2>&1 || info "k6 thresholds not met (see output); continuing"
sleep 45 # one recording-rule interval + scrape after the load
rate="$(prom_query 'notes_api:http_requests:rate5m' | jq -r '.data.result[0].value[1] // 0')"
awk -v r="$rate" 'BEGIN { exit !(r > 5) }' || fail "request rate after load is only $rate req/s"
pass "request rate recorded during the load: $(printf '%.1f' "$rate") req/s (5m average)"

# Evaluate every Prometheus panel query of the dashboard itself: each must return data.
empty=()
while IFS=$'\t' read -r panel expr; do
  expr="${expr//\$namespace/$NS}"
  n="$(prom_query "$expr" | jq '.data.result | length')"
  [[ "$n" -gt 0 ]] || empty+=("$panel")
done < <(jq -r '.panels[] | select(.datasource.type == "prometheus") | .title as $t | .targets[] | [$t, .expr] | @tsv' "$DASHBOARD")
[[ ${#empty[@]} -eq 0 ]] || fail "dashboard panels with no data: ${empty[*]}"
pass "all $(jq '[.panels[] | select(.datasource.type == "prometheus") | .targets[]] | length' "$DASHBOARD") Prometheus queries of the dashboard return data"

# --- 3. Logs searchable ------------------------------------------------------------------------
echo "=== 3. Logs searchable in Loki"
pod="$(k -n "$NS" get pods -l app.kubernetes.io/name=notes-api,app.kubernetes.io/component=api -o jsonpath='{.items[0].metadata.name}')"
query="{namespace=\"$NS\", pod=\"$pod\"} | json | logger=\"notes_api.access\" | status=\"201\""
start="$(( $(date +%s) - 900 ))000000000"
lines="$(k get --raw "$LOKI/query_range?query=$(urlencode "$query")&start=$start&limit=5" | jq '[.data.result[].values[]] | length')"
[[ "$lines" -gt 0 ]] || fail "no log lines for: $query"
pass "LogQL '$query' → $lines lines"

# --- 4. Induced failure fires an alert ---------------------------------------------------------
echo "=== 4. Induced failure: API scaled to 0 → NotesApiDown fires"
firing() { k get --raw "$AM/alerts?active=true&silenced=false&inhibited=false&filter=$(urlencode 'alertname=NotesApiDown')" | jq 'length'; }
[[ "$(firing)" == 0 ]] || fail "NotesApiDown is already firing before the drill"
replicas="$(k -n "$NS" get deploy notes-api -o jsonpath='{.spec.replicas}')"
k -n "$NS" scale deploy/notes-api --replicas=0 >/dev/null
info "scaled notes-api 0 (was $replicas); waiting for the alert (for: 1m + evaluation + scrape)"
fired=""
for _ in $(seq 1 60); do
  [[ "$(firing)" -gt 0 ]] && { fired=yes; break; }
  sleep 5
done
k -n "$NS" scale deploy/notes-api --replicas="$replicas" >/dev/null
[[ -n "$fired" ]] || fail "NotesApiDown did not fire within 5 minutes"
pass "NotesApiDown firing in Alertmanager ($(k get --raw "$AM/alerts?filter=$(urlencode 'alertname=NotesApiDown')" | jq -r '.[0].annotations.runbook_url'))"

k -n "$NS" rollout status deploy/notes-api --timeout=300s >/dev/null
for _ in $(seq 1 60); do
  [[ "$(firing)" == 0 ]] && break
  sleep 5
done
[[ "$(firing)" == 0 ]] || fail "NotesApiDown did not resolve after restoring $replicas replicas"
pass "restored $replicas replicas; NotesApiDown resolved"

echo "All observability checks passed."
