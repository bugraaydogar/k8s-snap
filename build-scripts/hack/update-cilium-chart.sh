#!/bin/bash
set -euo pipefail

VERSION="1.20.0"
DIR=$(realpath "$(dirname "${0}")")

CHARTS_PATH="$DIR/../../k8s/manifests/charts"
WORKDIR=$(mktemp -d "$CHARTS_PATH/.cilium-update.XXXXXX")
trap 'rm -rf -- "$WORKDIR"' EXIT

helm pull --repo https://helm.cilium.io cilium --version "$VERSION" \
    --untar --untardir "$WORKDIR"
patch --directory="$WORKDIR" --strip=1 --batch --forward --fuzz=0 \
    < "$CHARTS_PATH/cilium-cleanup-helper.patch"

helm template k8s "$WORKDIR/cilium" > /dev/null
helm template k8s "$WORKDIR/cilium" --set k8sInstallCleanupHelper=true > /dev/null
helm package "$WORKDIR/cilium" --destination "$WORKDIR"
mv -- "$WORKDIR/cilium-$VERSION.tgz" "$CHARTS_PATH/cilium-$VERSION.tgz"
