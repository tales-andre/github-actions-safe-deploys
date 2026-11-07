#!/usr/bin/env bash
# Deploys one image, pinned by digest, to the staging or production namespace and waits for it.
# If the new pods never become ready, it rolls the Deployment back to the previous revision
# and exits with an error, so a broken release never replaces a working one.
#
#   scripts/deploy.sh <staging|production> <registry/name@sha256:...>
#
# Optional environment: REGISTRY_USER and REGISTRY_PASSWORD (pull secret for a private
# registry, e.g. GHCR with the job's GITHUB_TOKEN), ROLLOUT_TIMEOUT (default 180s).
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

namespace="${1:-}"
image="${2:-}"
[[ "$namespace" =~ ^(staging|production)$ ]] || fail "usage: $0 <staging|production> <image@sha256:digest>"
# A tag can move; a digest cannot. Only digests are accepted, so what was tested is what runs.
[[ "$image" =~ ^[a-z0-9][a-z0-9._:/-]*@sha256:[a-f0-9]{64}$ ]] || fail "image must be pinned by digest (name@sha256:...), got: $image"

digest="${image##*@}"
registry="${image%%/*}"
timeout="${ROLLOUT_TIMEOUT:-180s}"

# Pull secret: real credentials when given, otherwise an empty one (local registry).
secret_file="$(mktemp)"
trap 'rm -f "$secret_file"' EXIT
chmod 600 "$secret_file"
if [ -n "${REGISTRY_USER:-}" ] && [ -n "${REGISTRY_PASSWORD:-}" ]; then
  auth="$(printf '%s:%s' "$REGISTRY_USER" "$REGISTRY_PASSWORD" | base64 | tr -d '\n')"
  printf '{"auths":{"%s":{"auth":"%s"}}}' "$registry" "$auth" >"$secret_file"
else
  printf '{"auths":{}}' >"$secret_file"
fi
kc -n "$namespace" create secret generic registry-pull --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson="$(native_path "$secret_file")" --dry-run=client -o yaml | kc apply -f - >/dev/null

log "deploying $image to $namespace"
sed "s|IMAGE_WITH_DIGEST|${image}|g" "$REPO_ROOT/deploy/k8s/app.yaml" | kc -n "$namespace" apply -f -
# Shows up in `kubectl rollout history`, so each revision names its digest.
kc -n "$namespace" annotate deployment/hello kubernetes.io/change-cause="image $digest" --overwrite >/dev/null

if kc -n "$namespace" rollout status deployment/hello --timeout="$timeout"; then
  log "$namespace now runs $digest"
  exit 0
fi

log "new pods did not become ready within $timeout; recent events:"
kc -n "$namespace" get pods -l app.kubernetes.io/name=hello -o wide || true
kc -n "$namespace" get events --sort-by=.lastTimestamp | tail -n 15 || true

if [ "$(kc -n "$namespace" get replicasets -l app.kubernetes.io/name=hello -o name | wc -l)" -gt 1 ]; then
  log "rolling $namespace back to the previous revision"
  kc -n "$namespace" rollout undo deployment/hello
  kc -n "$namespace" rollout status deployment/hello --timeout="$timeout"
  kc -n "$namespace" rollout history deployment/hello
  fail "release $digest failed in $namespace and was rolled back"
fi
fail "release $digest failed in $namespace (first deploy, nothing to roll back to)"
