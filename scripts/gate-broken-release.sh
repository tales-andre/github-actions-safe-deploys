#!/usr/bin/env bash
# Negative test, all in one job (a kind cluster does not survive between CI jobs):
#   1. a good release goes to production and passes the smoke test;
#   2. a deliberately broken release (crashes at start) is deployed: the rollout must fail,
#      deploy.sh must roll back by itself, and production must still serve the good digest;
#   3. the rollback.yml path: two good releases are recorded as tags, and the digest found
#      in production-previous is put back.
# Needs: scripts/kind-up.sh --local-registry first.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

cd "$REPO_ROOT"
image="localhost:${REGISTRY_PORT}/kettlebird-hello"
namespace="production"

log "1/3 good release v-good to $namespace"
docker build --quiet --build-arg APP_VERSION=v-good -t "$image:v-good" app >/dev/null
good="$(push_and_digest "$image:v-good")"
scripts/deploy.sh "$namespace" "$image@$good"
EXPECTED_VERSION=v-good scripts/smoke.sh "$namespace" "$good"
scripts/record-release.sh "$image" "$namespace" "$good"

log "2/3 broken release (same image, but the process exits at start)"
docker build --quiet --build-arg BASE_IMAGE="$image:v-good" -t "$image:v-broken" examples/broken-release >/dev/null
broken="$(push_and_digest "$image:v-broken")"
[ "$broken" != "$good" ] || fail "the broken image has the same digest as the good one"

status=0
GITHUB_ACTIONS="" ROLLOUT_TIMEOUT="${GATE_ROLLOUT_TIMEOUT:-45s}" scripts/deploy.sh "$namespace" "$image@$broken" || status=$?
[ "$status" -ne 0 ] || fail "deploy.sh accepted a release whose pods never became ready"
log "deploy.sh refused the broken release (exit $status), as expected"
EXPECTED_VERSION=v-good scripts/smoke.sh "$namespace" "$good"

log "3/3 rollback.yml path: release v-next, then put the previous digest back"
docker build --quiet --build-arg APP_VERSION=v-next -t "$image:v-next" app >/dev/null
next="$(push_and_digest "$image:v-next")"
scripts/deploy.sh "$namespace" "$image@$next"
EXPECTED_VERSION=v-next scripts/smoke.sh "$namespace" "$next"
scripts/record-release.sh "$image" "$namespace" "$next"

previous="$(scripts/previous-digest.sh "$image" "$namespace")"
[ "$previous" = "$good" ] || fail "production-previous is $previous, expected the good release $good"
scripts/deploy.sh "$namespace" "$image@$previous"
EXPECTED_VERSION=v-good scripts/smoke.sh "$namespace" "$good"
scripts/record-release.sh "$image" "$namespace" "$previous"

kc -n "$namespace" rollout history deployment/hello
log "gate passed: the broken release never replaced the good one, and rollback put the previous digest back"
