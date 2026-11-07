#!/usr/bin/env bash
# Prints the digest an environment ran before its last deploy (the <env>-previous tag that
# scripts/record-release.sh keeps). rollback.yml deploys this digest when none is given.
#
#   scripts/previous-digest.sh <registry/name> <staging|production>
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

image="${1:-}"
environment="${2:-}"
[[ "$image" =~ ^[a-z0-9][a-z0-9._:/-]*$ && "$image" != *@* ]] || fail "usage: $0 <registry/name> <staging|production>"
[[ "$environment" =~ ^(staging|production)$ ]] || fail "unknown environment: $environment"

status=0
digest="$(digest_of "$image:$environment-previous")" || status=$?
case "$status" in
  0) printf '%s\n' "$digest" ;;
  2) fail "no $environment-previous tag on $image: nothing to roll back to yet" ;;
  *) fail "could not read $image:$environment-previous" ;;
esac
