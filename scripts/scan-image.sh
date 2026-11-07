#!/usr/bin/env bash
# Scans a local image with Trivy, with the same gate as build.yml: fails on any CRITICAL or
# HIGH vulnerability that has a fix available.
#
#   scripts/scan-image.sh <image>      e.g. scripts/scan-image.sh kettlebird-hello:local
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

image="${1:-}"
[ -n "$image" ] || fail "usage: $0 <image>"

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "${TRIVY_CACHE_VOLUME:-safe-deploys-trivy-cache}:/root/.cache/trivy" \
  "$TRIVY_IMAGE" image --exit-code 1 --ignore-unfixed --severity CRITICAL,HIGH --scanners vuln --no-progress "$image"
