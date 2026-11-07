#!/usr/bin/env bash
# Static check that no long-lived cloud key is created or used.
# `terraform test` can only assert on resources a module declares; it cannot prove that a
# key resource is absent. This check reads the code instead:
#   - Terraform: no aws_iam_user / aws_iam_access_key / google_service_account_key / google_storage_hmac_key;
#   - workflows: no static AWS key inputs and no Google service account JSON key input.
#
#   scripts/check-no-static-keys.sh [path...]     default: infra .github/workflows
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

cd "$REPO_ROOT"
if [ "$#" -eq 0 ]; then set -- infra .github/workflows; fi

terraform_pattern='^[[:space:]]*resource[[:space:]]+"(aws_iam_user|aws_iam_access_key|google_service_account_key|google_storage_hmac_key)"'
workflow_pattern='(aws-access-key-id|aws-secret-access-key|AWS_SECRET_ACCESS_KEY|credentials_json)[[:space:]]*:'

hits=0
if found="$(grep -rnE --include='*.tf' "$terraform_pattern" "$@")"; then
  printf 'long-lived key resource:\n%s\n' "$found" >&2
  hits=1
fi
if found="$(grep -rnE --include='*.yml' --include='*.yaml' "$workflow_pattern" "$@")"; then
  printf 'static cloud key passed to a workflow step:\n%s\n' "$found" >&2
  hits=1
fi

[ "$hits" -eq 0 ] || fail "static cloud keys found in: $*"
log "no static cloud keys in: $*"
