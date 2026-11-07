#!/usr/bin/env bash
# Negative test: the deliberately unsafe example in examples/unsafe/ must be rejected by
# actionlint, by zizmor and by the static key check, each for the reasons expected.
# Exits 0 only if every check fails on it as it should.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

cd "$REPO_ROOT"
workflow="examples/unsafe/unsafe-workflow.yml"
failures=0

# expect_rejection <name> <output> <exit status> <needle>...
expect_rejection() {
  local name="$1" output="$2" status="$3" needle
  shift 3
  if [ "$status" -eq 0 ]; then
    printf '%s accepted the unsafe example\n' "$name" >&2
    failures=$((failures + 1))
    return
  fi
  for needle in "$@"; do
    if ! grep -qF -- "$needle" <<<"$output"; then
      printf '%s failed, but did not report "%s"\n' "$name" "$needle" >&2
      failures=$((failures + 1))
    fi
  done
  log "$name rejected it, as expected ($*)"
}

status=0
output="$(run_actionlint "$workflow" 2>&1)" || status=$?
printf '%s\n' "$output"
expect_rejection actionlint "$output" "$status" "potentially untrusted"

status=0
output="$(run_zizmor "$workflow" 2>&1)" || status=$?
printf '%s\n' "$output"
expect_rejection zizmor "$output" "$status" \
  dangerous-triggers excessive-permissions template-injection unpinned-uses artipacked

status=0
# GITHUB_ACTIONS unset: the expected failure should not show up as an error annotation on a green run.
output="$(GITHUB_ACTIONS="" "$REPO_ROOT/scripts/check-no-static-keys.sh" examples/unsafe 2>&1)" || status=$?
printf '%s\n' "$output"
expect_rejection check-no-static-keys "$output" "$status" "aws-secret-access-key" "aws_iam_access_key"

[ "$failures" -eq 0 ] || fail "$failures expectation(s) not met: a linter let something unsafe through"
log "gate passed: every check rejects the unsafe example"
