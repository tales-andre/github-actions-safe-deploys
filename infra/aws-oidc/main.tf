# One IAM role per GitHub environment. A workflow job can assume a role only when the
# short-lived OIDC token GitHub issues says it comes from this exact repository AND runs in
# that environment (repo:<owner>/<name>:environment:<env>). No access keys exist anywhere.

terraform {
  # mock_provider in `terraform test` needs 1.7 or newer.
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  github_issuer = "token.actions.githubusercontent.com"

  # Only one GitHub OIDC provider can exist per AWS account: create it here, or reuse it.
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  policy_attachments = {
    for pair in flatten([
      for env, arns in var.policy_arns : [for arn in arns : { env = env, arn = arn }]
    ]) : "${pair.env}/${pair.arn}" => pair
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.github_issuer}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://${local.github_issuer}"
}

resource "aws_iam_role" "deploy" {
  for_each = var.environments

  name                 = "${var.role_name_prefix}-${each.key}"
  description          = "Assumed by GitHub Actions jobs of ${var.github_repository} in the ${each.key} environment"
  max_session_duration = var.max_session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubActionsThisRepoThisEnvironment"
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        # StringEquals, never StringLike: no wildcard can widen who gets in.
        StringEquals = {
          "${local.github_issuer}:aud" = "sts.amazonaws.com"
          "${local.github_issuer}:sub" = "repo:${var.github_repository}:environment:${each.key}"
        }
      }
    }]
  })
}

# Nothing is attached by default: give each environment only what its deploy needs.
resource "aws_iam_role_policy_attachment" "deploy" {
  for_each = local.policy_attachments

  role       = aws_iam_role.deploy[each.value.env].name
  policy_arn = each.value.arn

  lifecycle {
    precondition {
      condition     = contains(var.environments, each.value.env)
      error_message = "policy_arns has a key that is not in environments."
    }
  }
}
