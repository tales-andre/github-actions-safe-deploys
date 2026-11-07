# Offline tests for infra/gcp-wif. The Google provider is mocked: no project, no credentials,
# nothing is created anywhere. `command = apply` runs against the mock so names exist.
# Run from infra/: terraform init -backend=false && terraform test
#
# What these tests cannot show: that no service account key exists. A test can only check
# resources the module declares, so scripts/check-no-static-keys.sh checks the code instead.

mock_provider "google" {
  mock_resource "google_iam_workload_identity_pool" {
    defaults = {
      name = "projects/123456789012/locations/global/workloadIdentityPools/github"
    }
  }

  mock_resource "google_iam_workload_identity_pool_provider" {
    defaults = {
      name = "projects/123456789012/locations/global/workloadIdentityPools/github/providers/github-actions"
    }
  }

  mock_resource "google_service_account" {
    defaults = {
      name  = "projects/kettlebird-demo/serviceAccounts/gh-deploy@kettlebird-demo.iam.gserviceaccount.com"
      email = "gh-deploy@kettlebird-demo.iam.gserviceaccount.com"
    }
  }
}

variables {
  project_id        = "kettlebird-demo"
  github_repository = "kettlebird/github-actions-safe-deploys"
}

run "pool_accepts_tokens_from_this_repository_only" {
  command = apply

  module {
    source = "./gcp-wif"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository == 'kettlebird/github-actions-safe-deploys'"
    error_message = "The provider must refuse tokens from any other repository."
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.oidc[0].issuer_uri == "https://token.actions.githubusercontent.com"
    error_message = "The provider must trust GitHub's OIDC issuer only."
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_mapping["google.subject"] == "assertion.sub"
    error_message = "google.subject must be the token's sub, which the bindings match exactly."
  }

  assert {
    condition     = output.workload_identity_provider == "projects/123456789012/locations/global/workloadIdentityPools/github/providers/github-actions"
    error_message = "The provider name must be exported for the GitHub variable."
  }
}

run "each_service_account_is_bound_to_its_own_environment" {
  command = apply

  module {
    source = "./gcp-wif"
  }

  assert {
    condition     = toset(keys(google_service_account_iam_member.github_environment)) == toset(["staging", "production"])
    error_message = "Expected one binding per environment."
  }

  assert {
    condition = alltrue([
      for env, binding in google_service_account_iam_member.github_environment :
      binding.member == "principal://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/github/subject/repo:kettlebird/github-actions-safe-deploys:environment:${env}" &&
      binding.role == "roles/iam.workloadIdentityUser"
    ])
    error_message = "Each binding must name the exact subject of that environment, not a principalSet."
  }

  assert {
    condition = alltrue([
      for binding in google_service_account_iam_member.github_environment :
      !strcontains(binding.member, "principalSet") && !strcontains(binding.member, "*")
    ])
    error_message = "No principalSet and no wildcard may be granted impersonation."
  }

  assert {
    condition     = google_service_account.deploy["production"].account_id == "gh-deploy-production"
    error_message = "Service account IDs must be <prefix>-<environment>."
  }
}

run "service_accounts_get_no_project_roles_unless_asked" {
  command = plan

  module {
    source = "./gcp-wif"
  }

  assert {
    condition     = length(google_project_iam_member.deploy) == 0
    error_message = "No project role may be granted by default."
  }
}

run "owner_id_is_checked_when_given" {
  command = plan

  module {
    source = "./gcp-wif"
  }

  variables {
    github_repository_owner_id = "424242"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository == 'kettlebird/github-actions-safe-deploys' && assertion.repository_owner_id == '424242'"
    error_message = "The owner ID must be added to the condition."
  }
}

run "rejects_a_wildcard_repository" {
  command = plan

  module {
    source = "./gcp-wif"
  }

  variables {
    github_repository = "*/*"
  }

  expect_failures = [var.github_repository]
}

run "rejects_owner_or_editor_for_a_deploy_account" {
  command = plan

  module {
    source = "./gcp-wif"
  }

  variables {
    project_roles = {
      production = ["roles/editor"]
    }
  }

  expect_failures = [var.project_roles]
}

run "roles_bind_only_to_the_named_environment" {
  command = apply

  module {
    source = "./gcp-wif"
  }

  variables {
    project_roles = {
      production = ["roles/run.developer"]
    }
  }

  assert {
    condition = (
      keys(google_project_iam_member.deploy) == ["production/roles/run.developer"] &&
      google_project_iam_member.deploy["production/roles/run.developer"].role == "roles/run.developer" &&
      google_project_iam_member.deploy["production/roles/run.developer"].member == "serviceAccount:${google_service_account.deploy["production"].email}"
    )
    error_message = "The role must go to the production service account only."
  }
}

run "rejects_roles_for_an_unknown_environment" {
  command = plan

  module {
    source = "./gcp-wif"
  }

  variables {
    project_roles = {
      qa = ["roles/run.developer"]
    }
  }

  expect_failures = [google_project_iam_member.deploy]
}
