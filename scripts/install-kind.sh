#!/usr/bin/env bash
# Installs a pinned kind release after checking its SHA-256 against the value written here.
# Usage: scripts/install-kind.sh            (installs to $KIND_INSTALL_DIR, default ~/.local/bin)
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

KIND_VERSION="v0.33.0"
dest="${KIND_INSTALL_DIR:-$HOME/.local/bin}"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
  linux | darwin) exe="kind" ;;
  mingw* | msys* | cygwin*) os="windows" exe="kind.exe" ;;
  *) fail "unsupported OS: $os" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch="amd64" ;;
  aarch64 | arm64) arch="arm64" ;;
  *) fail "unsupported CPU: $(uname -m)" ;;
esac

# From the .sha256sum files published with kind v0.33.0.
case "$os-$arch" in
  linux-amd64) want="aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d" ;;
  linux-arm64) want="20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2" ;;
  darwin-amd64) want="5a99f26f57246dc9319dd294803313197a0f34d33c525b3ea8b655db5916ece0" ;;
  darwin-arm64) want="0c8c7dbe5e23594a198b786c4bc13dacc101fa6196b0cb0b23a1ca44e61f4b4f" ;;
  windows-amd64) want="4b22adaa135368c5a465d56bbd8e520cbea87272a06ca00b6078e7b81515c9fc" ;;
  *) fail "no pinned checksum for $os-$arch" ;;
esac

if command -v kind >/dev/null 2>&1 && kind version | grep -q "^kind ${KIND_VERSION} "; then
  log "kind ${KIND_VERSION} already installed at $(command -v kind)"
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
log "downloading kind ${KIND_VERSION} for $os-$arch"
curl -fsSL --retry 3 -o "$tmp" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-${os}-${arch}"

if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "$tmp" | cut -d ' ' -f 1)"; else got="$(shasum -a 256 "$tmp" | cut -d ' ' -f 1)"; fi
[ "$got" = "$want" ] || fail "checksum mismatch for kind: got $got, want $want"

mkdir -p "$dest"
install -m 0755 "$tmp" "$dest/$exe"
log "installed $dest/$exe"

# In GitHub Actions, later steps find it on PATH.
if [ -n "${GITHUB_PATH:-}" ]; then printf '%s\n' "$dest" >>"$GITHUB_PATH"; fi
