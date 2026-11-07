#!/usr/bin/env bash
# Creates the throwaway cluster (kind) and the staging and production namespaces.
#   scripts/kind-up.sh                    cluster only (release.yml pulls images from GHCR)
#   scripts/kind-up.sh --local-registry   also a registry on localhost:5001 the cluster can pull from
#                                         (local runs and the broken-release gate)
# Remove it all with scripts/kind-down.sh.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

local_registry=false
case "${1:-}" in
  "") ;;
  --local-registry) local_registry=true ;;
  *) fail "usage: $0 [--local-registry]" ;;
esac

command -v kind >/dev/null 2>&1 || fail "kind not found: run scripts/install-kind.sh"
mkdir -p "$(dirname "$DEPLOY_KUBECONFIG")"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  log "reusing kind cluster $CLUSTER"
  kind export kubeconfig --name "$CLUSTER" --kubeconfig "$DEPLOY_KUBECONFIG"
else
  log "creating kind cluster $CLUSTER ($KIND_NODE_IMAGE)"
  kind create cluster --name "$CLUSTER" --image "$KIND_NODE_IMAGE" --kubeconfig "$DEPLOY_KUBECONFIG" --wait 120s
fi

if $local_registry; then
  # Same setup as kind's documented local registry: localhost:5001 on the host, and the
  # nodes' containerd told to reach it as $REGISTRY_NAME:5000 on the kind network.
  if [ "$(docker inspect -f '{{.State.Running}}' "$REGISTRY_NAME" 2>/dev/null || true)" != "true" ]; then
    docker rm -f "$REGISTRY_NAME" >/dev/null 2>&1 || true
    log "starting local registry on localhost:$REGISTRY_PORT"
    docker run -d -p "127.0.0.1:${REGISTRY_PORT}:5000" --network bridge --name "$REGISTRY_NAME" "$REGISTRY_IMAGE" >/dev/null
  fi
  registry_dir="/etc/containerd/certs.d/localhost:${REGISTRY_PORT}"
  for node in $(kind get nodes --name "$CLUSTER"); do
    docker exec "$node" mkdir -p "$registry_dir"
    printf '[host."http://%s:5000"]\n' "$REGISTRY_NAME" | docker exec -i "$node" cp /dev/stdin "$registry_dir/hosts.toml"
  done
  if [ "$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' "$REGISTRY_NAME")" = "null" ]; then
    docker network connect kind "$REGISTRY_NAME"
  fi
fi

kc apply -f "$REPO_ROOT/deploy/k8s/namespaces.yaml"
log "cluster ready; kubeconfig: $DEPLOY_KUBECONFIG"
