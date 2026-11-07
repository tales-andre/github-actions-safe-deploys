# Offline tests for infra/aws-oidc. The AWS provider is mocked: no account, no credentials,
# nothing is created anywhere. `command = apply` runs against the mock so ARNs exist.
# Run from infra/: terraform init -backend=false && terraform test

mock_provider "aws" {
  # The provider validates ARN-shaped arguments, so mocked ARNs must look real.
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_data "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/github-deploy-mock"
    }
  }
}

variables {
  github_repository = "kettlebird/github-actions-safe-deploys"
}

run "each_role_trusts_only_this_repo_and_its_own_environment" {
  command = apply

  module {
    source = "./aws-oidc"
  }

  assert {
    condition     = toset(keys(aws_iam_role.deploy)) == toset(["staging", "production"])
    error_message = "Expected one role per environment."
  }

  assert {
    condition = alltrue([
      for env, role in aws_iam_role.deploy :
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:kettlebird/github-actions-safe-deploys:environment:${env}"
    ])
    error_message = "Each role must trust exactly repo:<owner>/<name>:environment:<its environment>."
  }

  assert {
    condition = alltrue([
      for role in aws_iam_role.deploy :
      jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    ])
    error_message = "The audience must be sts.amazonaws.com."
  }

  assert {
    condition = alltrue([
      for role in aws_iam_role.deploy :
      length(jsondecode(role.assume_role_policy).Statement) == 1 &&
      jsondecode(role.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(role.assume_role_policy).Statement[0].Principal.Federated == aws_iam_openid_connect_provider.github[0].arn
    ])
    error_message = "The only way in must be the GitHub OIDC provider."
  }

  assert {
    condition = alltrue([
      for role in aws_iam_role.deploy :
      keys(jsondecode(role.assume_role_policy).Statement[0].Condition) == ["StringEquals"] &&
      !strcontains(role.assume_role_policy, "*")
    ])
    error_message = "No StringLike and no wildcard may appear in a trust policy."
  }

  assert {
    condition     = output.role_arns["production"] == "arn:aws:iam::123456789012:role/github-deploy-mock"
    error_message = "The role ARNs must be exported for the GitHub environment variables."
  }
}

run "roles_get_no_permissions_unless_asked" {
  command = plan

  module {
    source = "./aws-oidc"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.deploy) == 0
    error_message = "No policy may be attached by default."
  }
}

run "policies_attach_only_to_the_named_environment" {
  command = plan

  module {
    source = "./aws-oidc"
  }

  variables {
    policy_arns = {
      production = ["arn:aws:iam::123456789012:policy/kettlebird-eks-describe"]
    }
  }

  assert {
    condition = (
      keys(aws_iam_role_policy_attachment.deploy) == ["production/arn:aws:iam::123456789012:policy/kettlebird-eks-describe"] &&
      aws_iam_role_policy_attachment.deploy["production/arn:aws:iam::123456789012:policy/kettlebird-eks-describe"].role == "github-deploy-production"
    )
    error_message = "The policy must go to the production role only."
  }
}

run "reuses_an_existing_oidc_provider" {
  command = apply

  module {
    source = "./aws-oidc"
  }

  variables {
    create_oidc_provider = false
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "Must not create a second GitHub OIDC provider."
  }

  assert {
    condition     = output.oidc_provider_arn == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    error_message = "Must trust the existing provider."
  }
}

run "rejects_a_wildcard_repository" {
  command = plan

  module {
    source = "./aws-oidc"
  }

  variables {
    github_repository = "kettlebird/*"
  }

  expect_failures = [var.github_repository]
}

run "rejects_a_wildcard_environment" {
  command = plan

  module {
    source = "./aws-oidc"
  }

  variables {
    environments = ["*"]
  }

  expect_failures = [var.environments]
}

run "rejects_admin_policies" {
  command = plan

  module {
    source = "./aws-oidc"
  }

  variables {
    policy_arns = {
      production = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
  }

  expect_failures = [var.policy_arns]
}

run "rejects_policies_for_an_unknown_environment" {
  command = plan

  module {
    source = "./aws-oidc"
  }

  variables {
    policy_arns = {
      qa = ["arn:aws:iam::123456789012:policy/kettlebird-eks-describe"]
    }
  }

  expect_failures = [aws_iam_role_policy_attachment.deploy]
}
