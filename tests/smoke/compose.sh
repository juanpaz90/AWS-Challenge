#!/usr/bin/env bash
# End-to-end smoke test for the Docker Compose stack (Phase 4, story S1).
# Expects the stack to be running (`task compose:up`). Requires curl and jq.
set -euo pipefail

cd "$(dirname "$0")/../../app"
BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
if [[ -z "${COMPOSE:-}" ]]; then
  if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"; else COMPOSE="docker-compose"; fi
fi

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*" >&2; exit 1; }

wait_ready() {
  for _ in $(seq 1 60); do
    curl -fsS "$BASE_URL/readyz" >/dev/null 2>&1 && return 0
    sleep 1
  done
  fail "API did not become ready at $BASE_URL/readyz"
}

get_note() { curl -fsS "$BASE_URL/notes/$1" | jq -r .content; }

wait_ready

# 1. Probes and service info
[[ "$(curl -fsS -o /dev/null -w '%{http_code}' "$BASE_URL/healthz")" == 200 ]] || fail "/healthz"
[[ "$(curl -fsS "$BASE_URL/readyz" | jq -r .database)" == ok ]] || fail "/readyz"
info="$(curl -fsS "$BASE_URL/")"
jq -e '.pod != "" and .message != "" and .version != ""' <<<"$info" >/dev/null || fail "GET / -> $info"
pass "probes and service info ($(jq -c . <<<"$info"))"

# 2. CRUD round trip
marker="smoke-$(date +%s)-$RANDOM"
id="$(curl -fsS -X POST "$BASE_URL/notes" -H 'Content-Type: application/json' \
  -d "{\"title\":\"smoke\",\"content\":\"$marker\"}" | jq -r .id)"
[[ "$(get_note "$id")" == "$marker" ]] || fail "created note $id not readable"
pass "create + read note $id"

# 3. Data survives a database container restart
$COMPOSE restart db >/dev/null 2>&1
wait_ready
[[ "$(get_note "$id")" == "$marker" ]] || fail "note lost after db restart"
pass "data survives db container restart"

# 4. Data survives recreating every container (named volume persists)
$COMPOSE down >/dev/null 2>&1
$COMPOSE up -d --no-build >/dev/null 2>&1
wait_ready
[[ "$(get_note "$id")" == "$marker" ]] || fail "note lost after down/up"
pass "data survives full stack recreation (down/up without -v)"

# 5. Hardening
uid="$($COMPOSE exec -T api id -u)"
[[ "$uid" != 0 ]] || fail "API runs as root"
if $COMPOSE exec -T api sh -c 'touch /app/write-test' >/dev/null 2>&1; then fail "root filesystem is writable"; fi
pass "runs as uid $uid with a read-only root filesystem"

# 6. Database is not published on the host
# `compose port` exits 0 even when nothing is published, so read the real host bindings.
bindings="$(docker inspect -f '{{json .NetworkSettings.Ports}}' "$($COMPOSE ps -q db)")"
jq -e 'all(.[]; . == null)' <<<"$bindings" >/dev/null || fail "db has host port bindings: $bindings"
pass "database port not published on the host"

# 7. Metrics and structured logs
curl -fsS "$BASE_URL/metrics" | grep -q 'http_requests_total{handler="/notes/{note_id}"' \
  || fail "route-templated request metric missing"
pass "metrics exposed with route-template labels"
$COMPOSE logs --no-log-prefix api 2>/dev/null | grep '^{' | tail -n 50 \
  | jq -e 'select(.logger == "notes_api.access" and .pod != null and .request_id != null)' >/dev/null \
  || fail "no structured access log lines"
pass "JSON access logs with pod and request id"

# 8. Graceful shutdown on SIGTERM: clean exit and lifespan shutdown ran
$COMPOSE stop api >/dev/null 2>&1
container="$($COMPOSE ps -a -q api)"
code="$(docker inspect -f '{{.State.ExitCode}}' "$container")"
[[ "$code" == 0 ]] || fail "API exited with code $code on SIGTERM"
$COMPOSE logs --no-log-prefix api 2>/dev/null | grep '^{' | jq -e 'select(.message == "shutdown complete")' >/dev/null \
  || fail "no 'shutdown complete' log line"
$COMPOSE start api >/dev/null 2>&1
wait_ready
pass "graceful shutdown on SIGTERM (exit 0, pool disposed)"

echo "All compose smoke checks passed."
