#!/usr/bin/env bash
# Lint every chart in charts/ and validate the rendered manifests with kubeconform,
# once per values file (values.yaml plus values-<env>.yaml overlays).
#
# KUBERNETES_VERSION pins the schema version to the cluster/EKS minor (ADR-0001).
set -euo pipefail

KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.35.0}"
# Community CRD schemas (HTTPRoute, ServiceMonitor, CNPG Cluster, ...)
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

shopt -s nullglob
charts=(charts/*/Chart.yaml infra/modules/*/charts/*/Chart.yaml)
if [[ ${#charts[@]} -eq 0 ]]; then
  echo "No charts found — nothing to validate."
  exit 0
fi

for chart_file in "${charts[@]}"; do
  chart="$(dirname "$chart_file")"
  name="$(basename "$chart")"

  # Values Terraform/CI inject at deploy time (image repository, git-SHA tag) come from an
  # optional ci/validate-values.yaml (chart-testing convention).
  ci_args=()
  [[ -f "$chart/ci/validate-values.yaml" ]] && ci_args=(-f "$chart/ci/validate-values.yaml")

  # Validate every environment overlay on top of values.yaml, or values.yaml alone.
  overlays=("$chart"/values-*.yaml)
  [[ ${#overlays[@]} -eq 0 ]] && overlays=("")

  for overlay in "${overlays[@]}"; do
    args=(-f "$chart/values.yaml")
    [[ -n "$overlay" ]] && args+=(-f "$overlay")
    args+=("${ci_args[@]+"${ci_args[@]}"}")
    label="${overlay:+${overlay##*/}}"; label="${label:-values.yaml}"

    echo "==> helm lint ${chart} (${label})"
    helm lint --strict "$chart" "${args[@]}"

    echo "==> kubeconform ${chart} (${label})"
    helm template "$name" "$chart" "${args[@]}" |
      kubeconform -strict -summary \
        -kubernetes-version "$KUBERNETES_VERSION" \
        -schema-location default \
        -schema-location "$CRD_SCHEMAS"
  done
done
