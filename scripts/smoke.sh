#!/usr/bin/env bash
# Smoke test after a deploy: every ready pod runs the expected digest, and the service
# answers through `kubectl port-forward`.
#
#   scripts/smoke.sh <staging|production> [sha256:<digest>]
#
# Optional environment: EXPECTED_VERSION (checked against GET /).
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

namespace="${1:-}"
expected="${2:-}"
[[ "$namespace" =~ ^(staging|production)$ ]] || fail "usage: $0 <staging|production> [sha256:digest]"

kc -n "$namespace" rollout status deployment/hello --timeout=120s >/dev/null

if [ -n "$expected" ]; then
  [[ "$expected" =~ ^sha256:[a-f0-9]{64}$ ]] || fail "not a digest: $expected"
  spec_image="$(kc -n "$namespace" get deployment hello -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [[ "$spec_image" == *"@$expected" ]] || fail "$namespace is set to $spec_image, expected digest $expected"

  ready_images="$(kc -n "$namespace" get pods -l app.kubernetes.io/name=hello \
    -o jsonpath='{range .items[*]}{range .status.containerStatuses[?(@.ready==true)]}{.imageID}{"\n"}{end}{end}')"
  [ -n "$ready_images" ] || fail "no ready pods in $namespace"
  while read -r image_id; do
    [[ "$image_id" == *"@$expected" ]] || fail "a ready pod in $namespace runs $image_id, expected $expected"
  done <<<"$ready_images"
  log "every ready pod in $namespace runs $expected"
fi

pf_log="$(mktemp)"
kc -n "$namespace" port-forward svc/hello :80 >"$pf_log" 2>&1 &
pf_pid=$!
trap 'kill "$pf_pid" 2>/dev/null || true; rm -f "$pf_log"' EXIT

port=""
for _ in $(seq 1 30); do
  port="$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) .*/\1/p' "$pf_log" | head -n 1)"
  [ -n "$port" ] && break
  sleep 1
done
[ -n "$port" ] || { cat "$pf_log" >&2; fail "kubectl port-forward did not start"; }

health="$(curl -fsS --retry 5 --retry-delay 1 --retry-all-errors "http://127.0.0.1:${port}/healthz")"
[ "$health" = "ok" ] || fail "/healthz answered '$health'"

body="$(curl -fsS --retry 3 --retry-delay 1 --retry-all-errors "http://127.0.0.1:${port}/")"
log "$namespace answers: $body"
if [ -n "${EXPECTED_VERSION:-}" ]; then
  [[ "$body" == *"\"version\":\"${EXPECTED_VERSION}\""* ]] || fail "expected version $EXPECTED_VERSION in $namespace"
fi
log "smoke test passed in $namespace"
