#!/usr/bin/env bash
# Checks for the local/20-platform stack (Phase 6, story S3).
set -euo pipefail

CONTEXT="${CONTEXT:-kind-notes-local}"
DOMAIN="${DOMAIN:-localtest.me}"
k() { kubectl --context "$CONTEXT" "$@"; }

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*" >&2; exit 1; }

# 1. Nodes Ready (Calico installed)
k wait --for=condition=Ready nodes --all --timeout=180s >/dev/null || fail "nodes not Ready"
pass "all nodes Ready (Calico CNI)"

# 2. Every Helm release deployed
expected="alloy calico cert-manager cnpg envoy-gateway kube-prometheus-stack loki metrics-server platform-config"
releases="$(helm --kube-context "$CONTEXT" list -A -o json | jq -r '.[] | select(.status=="deployed") | .name' | sort | xargs)"
[[ "$releases" == "$expected" ]] || fail "deployed releases: '$releases' (expected '$expected')"
pass "9 Helm releases deployed (+ Calico CRDs applied by Terraform)"

# 3. Workloads healthy in every platform namespace
for ns in calico-system tigera-operator cert-manager gateway cnpg-system monitoring kube-system; do
  for kind in deployment daemonset statefulset; do
    for obj in $(k -n "$ns" get "$kind" -o name 2>/dev/null); do
      k -n "$ns" rollout status "$obj" --timeout=300s >/dev/null || fail "$ns/$obj not rolled out"
    done
  done
done
pass "all Deployments/DaemonSets/StatefulSets rolled out"

# 4. Pod Security labels
for ns in cert-manager gateway cnpg-system; do
  [[ "$(k get ns "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')" == restricted ]] \
    || fail "$ns is not PSA restricted"
done
pass "cert-manager, gateway, cnpg-system enforce PSA restricted (tigera-operator, monitoring: documented privileged)"

# 5. metrics-server serves resource metrics (needed by the HPA)
for _ in $(seq 1 30); do k top nodes >/dev/null 2>&1 && break; sleep 5; done
k top nodes >/dev/null 2>&1 || fail "kubectl top nodes failed"
pass "metrics-server serving node metrics"

# 6. TLS chain and Gateway
k wait --for=condition=Ready clusterissuer/local-ca --timeout=120s >/dev/null || fail "ClusterIssuer local-ca not Ready"
k -n gateway wait --for=condition=Ready certificate/platform-tls --timeout=120s >/dev/null || fail "gateway certificate not Ready"
k -n gateway wait --for=condition=Programmed gateway/platform --timeout=180s >/dev/null || fail "Gateway not Programmed"
pass "local CA issuer, wildcard certificate and Gateway ready"

svc="$(k -n gateway get svc -l gateway.envoyproxy.io/owning-gateway-name=platform -o json)"
jq -e '.items[0].spec.type == "NodePort" and .items[0].spec.externalTrafficPolicy == "Cluster"' <<<"$svc" >/dev/null \
  || fail "Envoy service is not a NodePort with externalTrafficPolicy=Cluster"
jq -e '[.items[0].spec.ports[].nodePort] | sort == [30080, 30443]' <<<"$svc" >/dev/null || fail "NodePorts are not 30080/30443"
pass "Envoy service: NodePort 30080/30443, externalTrafficPolicy=Cluster"

# 7. Grafana reachable from the host through the gateway, TLS verified against the local CA
ca="$(mktemp)"; trap 'rm -f "$ca"' EXIT
k -n cert-manager get secret local-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >"$ca"
code=""
for _ in $(seq 1 30); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --cacert "$ca" "https://grafana.${DOMAIN}/api/health" || true)"
  [[ "$code" == 200 ]] && break
  sleep 5
done
[[ "$code" == 200 ]] || fail "https://grafana.${DOMAIN}/api/health returned '$code'"
pass "https://grafana.${DOMAIN} → 200 with a certificate trusted by the local CA"

[[ "$(curl -sS -o /dev/null -w '%{http_code}' "http://grafana.${DOMAIN}/")" == 301 ]] || fail "HTTP does not redirect to HTTPS"
pass "plain HTTP redirects to HTTPS (301)"

# 8. Logs flow Alloy → Loki
labels=""
for _ in $(seq 1 30); do
  labels="$(k get --raw "/api/v1/namespaces/monitoring/services/loki:3100/proxy/loki/api/v1/label/namespace/values" 2>/dev/null || true)"
  jq -e '.data | index("monitoring")' <<<"$labels" >/dev/null 2>&1 && break
  sleep 5
done
jq -e '.data | index("monitoring")' <<<"$labels" >/dev/null 2>&1 || fail "Loki has no logs labelled namespace=monitoring: $labels"
pass "Loki receives pod logs from Alloy (namespaces: $(jq -r '.data | join(",")' <<<"$labels"))"

# 9. Local registry documented in-cluster
k -n kube-public get configmap local-registry-hosting >/dev/null || fail "local-registry-hosting ConfigMap missing"
pass "local-registry-hosting ConfigMap published"

echo "All 20-platform checks passed."
