#!/usr/bin/env bash
# Checks that nothing in the pipeline can change under it:
#   - every external action in .github/workflows is pinned to a full commit SHA, with the
#     release it came from in a comment (uses: owner/repo@<40 hex> # vX.Y.Z);
#   - every tool image in scripts/lib.sh is pinned by digest;
#   - build.yml uses the same Trivy image as scripts/lib.sh.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

problems=0
cd "$REPO_ROOT"

while IFS= read -r line; do
  file="${line%%:*}"
  ref="$(sed -E 's/^[^:]+:[0-9]+:[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*//' <<<"$line")"
  case "$ref" in
    ./*) continue ;;
  esac
  if ! [[ "$ref" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]+(\.[0-9]+)*$ ]]; then
    printf 'not pinned to a commit SHA with its version: %s: %s\n' "$file" "$ref" >&2
    problems=$((problems + 1))
  fi
done < <(grep -rnE '^[[:space:]]*(-[[:space:]]*)?uses:' .github/workflows)

for var in TRIVY_IMAGE ACTIONLINT_IMAGE ZIZMOR_IMAGE REGISTRY_IMAGE KIND_NODE_IMAGE; do
  value="${!var}"
  if ! [[ "$value" =~ @sha256:[a-f0-9]{64}$ ]]; then
    printf 'not pinned by digest: %s=%s\n' "$var" "$value" >&2
    problems=$((problems + 1))
  fi
done

if ! grep -qF "$TRIVY_IMAGE" .github/workflows/build.yml; then
  printf 'build.yml does not use the Trivy image pinned in scripts/lib.sh (%s)\n' "$TRIVY_IMAGE" >&2
  problems=$((problems + 1))
fi

[ "$problems" -eq 0 ] || fail "$problems pinning problem(s)"
log "all actions pinned to commit SHAs, all tool images pinned by digest"
