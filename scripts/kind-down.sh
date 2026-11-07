#!/usr/bin/env bash
# Deletes the throwaway cluster and the local registry that scripts/kind-up.sh created.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  kind delete cluster --name "$CLUSTER" --kubeconfig "$DEPLOY_KUBECONFIG"
fi
docker rm -f "$REGISTRY_NAME" >/dev/null 2>&1 || true
rm -f "$DEPLOY_KUBECONFIG"
log "removed cluster $CLUSTER and the local registry"
