#!/usr/bin/env bash
# Lints the GitHub Actions setup with actionlint and zizmor (pinned container images).
# Both must report nothing for this repository's own workflows.
#
#   scripts/lint-workflows.sh                  actionlint on .github/workflows, zizmor on the repository
#                                              (workflows and dependabot.yml; examples/ is not collected)
#   scripts/lint-workflows.sh <file.yml>...    lint the given files instead
#
# With GH_TOKEN set, zizmor also runs its online audits (impostor commits, known-vulnerable actions).
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

status=0

log "actionlint ${*:-.github/workflows}"
run_actionlint "$@" || status=1

log "zizmor ${*:-.}"
if [ "$#" -eq 0 ]; then set -- .; fi
run_zizmor "$@" || status=1

[ "$status" -eq 0 ] && log "workflows are clean"
exit "$status"
