#!/usr/bin/env bash
# Lint every chart in charts/ and validate the rendered manifests with kubeconform,
# once per values file (values.yaml plus values-<env>.yaml overlays).
#
# KUBERNETES_VERSION pins the schema version (set it to the EKS minor, e.g. 1.34.0).
set -euo pipefail

KUBERNETES_VERSION="${KUBERNETES_VERSION:-master}"
# Community CRD schemas (HTTPRoute, ServiceMonitor, CNPG Cluster, ...)
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

shopt -s nullglob
charts=(charts/*/Chart.yaml)
if [[ ${#charts[@]} -eq 0 ]]; then
  echo "No charts found under charts/ — nothing to validate."
  exit 0
fi

for chart_file in "${charts[@]}"; do
  chart="$(dirname "$chart_file")"
  echo "==> helm lint ${chart}"
  helm lint --strict "$chart"

  for values in "$chart"/values.yaml "$chart"/values-*.yaml; do
    [[ -f "$values" ]] || continue
    args=(-f "$chart/values.yaml")
    [[ "$values" != "$chart/values.yaml" ]] && args+=(-f "$values")

    echo "==> kubeconform ${chart} (${values##*/})"
    helm template "$(basename "$chart")" "$chart" "${args[@]}" |
      kubeconform -strict -summary \
        -kubernetes-version "$KUBERNETES_VERSION" \
        -schema-location default \
        -schema-location "$CRD_SCHEMAS"
  done
done
