#!/usr/bin/env bash
# Checks that the actions and tool images the pipeline runs are pinned:
#   - every external action in .github/workflows is pinned to a full commit SHA, with the
#     release it came from in a comment (uses: owner/repo@<40 hex> # vX.Y.Z);
#   - every tool image in scripts/lib.sh is pinned by digest;
#   - build.yml uses the same Trivy image as scripts/lib.sh;
#   - no Dockerfile pulls a BuildKit frontend ("# syntax=...") by a tag.
# Not checked on purpose: the app's base image (app/Dockerfile) is a tag, rebuilt upstream for
# security fixes and scanned by Trivy on every build.
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

# A "# syntax=" parser directive makes BuildKit pull that frontend image before the build.
while IFS= read -r line; do
  if ! [[ "$line" =~ @sha256:[a-f0-9]{64}[[:space:]]*$ ]]; then
    printf 'BuildKit frontend not pinned by digest: %s\n' "$line" >&2
    problems=$((problems + 1))
  fi
done < <(find . \( -name .git -o -name .terraform -o -name .kind -o -name node_modules \) -prune -o \
  -type f \( -name 'Dockerfile' -o -name '*.Dockerfile' -o -name 'Dockerfile.*' \) -print0 |
  xargs -0 -r grep -HinE '^#[[:space:]]*syntax[[:space:]]*=' || true)

if ! grep -qF "$TRIVY_IMAGE" .github/workflows/build.yml; then
  printf 'build.yml does not use the Trivy image pinned in scripts/lib.sh (%s)\n' "$TRIVY_IMAGE" >&2
  problems=$((problems + 1))
fi

[ "$problems" -eq 0 ] || fail "$problems pinning problem(s)"
log "all actions pinned to commit SHAs, all tool images pinned by digest, no unpinned BuildKit frontend"
