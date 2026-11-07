# Shared settings and helpers for the scripts in this folder. Source it, don't run it.
# shellcheck shell=bash
# shellcheck disable=SC2034 # the settings here are used by the scripts that source this file

set -euo pipefail

# Git Bash on Windows rewrites /paths in arguments; turn that off and pass host paths
# through native_path instead. No effect on Linux or macOS.
export MSYS_NO_PATHCONV=1

native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

REPO_ROOT="$(native_path "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)")"
export REPO_ROOT

# Tool images, pinned by digest. CI and local runs use exactly these.
# build.yml repeats TRIVY_IMAGE (it must work when called from other repositories);
# scripts/check-pins.sh fails if the two drift apart.
TRIVY_IMAGE="aquasec/trivy:0.76.2@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb"
ACTIONLINT_IMAGE="rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667"
ZIZMOR_IMAGE="ghcr.io/zizmorcore/zizmor:1.32.0@sha256:3014cc8f68f663935f69b3c3e0e41f5ce102b268d97db13db0f62208747f860d"
REGISTRY_IMAGE="registry:3@sha256:38907510915c3f1604c7e83d6ab602ab3020d092f73bdaed8696773693ff768c"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0}"

# The throwaway cluster. The scripts never read or change your own kubeconfig:
# kind writes this file, and every kubectl call below uses only this file.
CLUSTER="${CLUSTER:-safe-deploys}"
DEPLOY_KUBECONFIG="${DEPLOY_KUBECONFIG:-$REPO_ROOT/.kind/kubeconfig}"
REGISTRY_NAME="${REGISTRY_NAME:-safe-deploys-registry}"
REGISTRY_PORT="${REGISTRY_PORT:-5001}"

kc() { kubectl --kubeconfig "$DEPLOY_KUBECONFIG" "$@"; }

log() { printf '==> %s\n' "$*" >&2; }

# In GitHub Actions the message also shows as an annotation on the run.
fail() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then printf '::error::%s\n' "$*"; else printf 'error: %s\n' "$*" >&2; fi
  exit 1
}

# Pushes a tag and prints the digest (sha256:...) the registry now holds for it.
push_and_digest() {
  local ref="$1" repo="${1%:*}" digest
  docker push --quiet "$ref" >/dev/null
  digest="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$ref" | sed -n "s|^${repo}@||p" | head -n 1)"
  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || fail "no digest for $ref after push"
  printf '%s\n' "$digest"
}

# Prints the digest a tag points to in the registry, without pulling the image.
# Returns 2 if the tag does not exist, 1 on any other error (so a registry outage is
# never mistaken for "no previous release").
digest_of() {
  local out digest
  if ! out="$(docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' 2>&1)"; then
    if grep -qiE 'not found|manifest unknown' <<<"$out"; then return 2; fi
    printf 'cannot read %s: %s\n' "$1" "$out" >&2
    return 1
  fi
  digest="$(sed -n 's/.*"digest":"\(sha256:[a-f0-9]\{64\}\)".*/\1/p' <<<"$out" | head -n 1)"
  [ -n "$digest" ] || { printf 'no digest in the answer for %s\n' "$1" >&2; return 1; }
  printf '%s\n' "$digest"
}

# Linters, from the pinned images. Set USE_LOCAL_TOOLS=1 to use actionlint/zizmor from PATH.
run_actionlint() {
  if [ "${USE_LOCAL_TOOLS:-}" = 1 ]; then (cd "$REPO_ROOT" && actionlint -color "$@"); return; fi
  docker run --rm -v "$REPO_ROOT:/repo" -w /repo "$ACTIONLINT_IMAGE" -color "$@"
}

run_zizmor() {
  local args=()
  # Online audits (impostor commits, known-vulnerable actions) need a GitHub token.
  [ -n "${GH_TOKEN:-}" ] || args+=(--offline)
  if [ "${USE_LOCAL_TOOLS:-}" = 1 ]; then (cd "$REPO_ROOT" && zizmor ${args[@]+"${args[@]}"} "$@"); return; fi
  docker run --rm -v "$REPO_ROOT:/repo" -w /repo -e GH_TOKEN "$ZIZMOR_IMAGE" ${args[@]+"${args[@]}"} "$@"
}
