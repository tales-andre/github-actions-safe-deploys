#!/usr/bin/env bash
# After a successful deploy, remembers what each environment runs, as registry tags:
#   <image>:<env>           the digest now running
#   <image>:<env>-previous  the digest it ran before (what rollback.yml puts back)
# Tags are only pointers: no image is rebuilt or re-pushed, the digests stay the same.
#
#   scripts/record-release.sh <registry/name> <staging|production> <sha256:digest>
#
# Needs `docker login` to the registry with write access.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

image="${1:-}"
environment="${2:-}"
digest="${3:-}"
[[ "$image" =~ ^[a-z0-9][a-z0-9._:/-]*$ && "$image" != *@* ]] || fail "usage: $0 <registry/name> <env> <sha256:digest>"
[[ "$environment" =~ ^(staging|production)$ ]] || fail "unknown environment: $environment"
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || fail "not a digest: $digest"

status=0
current="$(digest_of "$image:$environment")" || status=$?
case "$status" in
  0) ;;
  2) current="" && log "first release recorded for $environment" ;;
  *) fail "could not read the current $environment tag; not changing any tag" ;;
esac

if [ -n "$current" ] && [ "$current" != "$digest" ]; then
  docker buildx imagetools create --tag "$image:$environment-previous" "$image@$current"
  log "$environment-previous -> $current"
fi
docker buildx imagetools create --tag "$image:$environment" "$image@$digest"
log "$environment -> $digest"
