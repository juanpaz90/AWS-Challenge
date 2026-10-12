#!/usr/bin/env bash
# Installs CLI tools that have no official GitHub setup action, on linux/amd64 runners.
# Every download is verified against the checksum file published with the release.
# Versions match the README prerequisites; bump them together.
set -euo pipefail

KUBECONFORM_VERSION="${KUBECONFORM_VERSION:-v0.8.0}"
HADOLINT_VERSION="${HADOLINT_VERSION:-v2.15.1}"
TERRAFORM_DOCS_VERSION="${TERRAFORM_DOCS_VERSION:-v0.24.0}"
HELM_DOCS_VERSION="${HELM_DOCS_VERSION:-v1.14.2}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

mkdir -p "$BIN_DIR"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

# fetch <url> [<url> ...]: download into the working directory, failing on HTTP errors.
fetch() { for url in "$@"; do curl -fsSLO --retry 3 "$url"; done; }
# verify <checksum-file> <asset>: check one asset against a "<sha256>  <name>" style file.
verify() { grep -E "[ *]$2\$" "$1" | sha256sum --check --strict -; }

gh="https://github.com"

fetch "$gh/yannh/kubeconform/releases/download/$KUBECONFORM_VERSION/kubeconform-linux-amd64.tar.gz" \
      "$gh/yannh/kubeconform/releases/download/$KUBECONFORM_VERSION/CHECKSUMS"
verify CHECKSUMS kubeconform-linux-amd64.tar.gz
tar -xzf kubeconform-linux-amd64.tar.gz kubeconform && install -m 0755 kubeconform "$BIN_DIR/"

fetch "$gh/hadolint/hadolint/releases/download/$HADOLINT_VERSION/hadolint-linux-x86_64" \
      "$gh/hadolint/hadolint/releases/download/$HADOLINT_VERSION/checksums.sha256"
verify checksums.sha256 hadolint-linux-x86_64
install -m 0755 hadolint-linux-x86_64 "$BIN_DIR/hadolint"

fetch "$gh/terraform-docs/terraform-docs/releases/download/$TERRAFORM_DOCS_VERSION/terraform-docs-$TERRAFORM_DOCS_VERSION-linux-amd64.tar.gz" \
      "$gh/terraform-docs/terraform-docs/releases/download/$TERRAFORM_DOCS_VERSION/terraform-docs-$TERRAFORM_DOCS_VERSION.sha256sum"
verify "terraform-docs-$TERRAFORM_DOCS_VERSION.sha256sum" "terraform-docs-$TERRAFORM_DOCS_VERSION-linux-amd64.tar.gz"
tar -xzf "terraform-docs-$TERRAFORM_DOCS_VERSION-linux-amd64.tar.gz" terraform-docs && install -m 0755 terraform-docs "$BIN_DIR/"

fetch "$gh/norwoodj/helm-docs/releases/download/$HELM_DOCS_VERSION/helm-docs_${HELM_DOCS_VERSION#v}_Linux_x86_64.tar.gz" \
      "$gh/norwoodj/helm-docs/releases/download/$HELM_DOCS_VERSION/checksums.txt"
verify checksums.txt "helm-docs_${HELM_DOCS_VERSION#v}_Linux_x86_64.tar.gz"
tar -xzf "helm-docs_${HELM_DOCS_VERSION#v}_Linux_x86_64.tar.gz" helm-docs && install -m 0755 helm-docs "$BIN_DIR/"

echo "$BIN_DIR" >>"${GITHUB_PATH:-/dev/null}"
printf '%-15s %s\n' kubeconform "$("$BIN_DIR/kubeconform" -v 2>&1)" \
  hadolint "$("$BIN_DIR/hadolint" --version 2>&1)" \
  terraform-docs "$("$BIN_DIR/terraform-docs" --version 2>&1)" \
  helm-docs "$("$BIN_DIR/helm-docs" --version 2>&1)"
