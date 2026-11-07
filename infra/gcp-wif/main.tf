# Workload Identity Federation for GitHub Actions: the pool only accepts tokens from one
# repository, and each environment's service account can only be impersonated by jobs of
# that repository running in that environment. No service account key is ever created.

terraform {
  # mock_provider in `terraform test` needs 1.7 or newer.
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

locals {
  repository_condition = "assertion.repository == '${var.github_repository}'"
  owner_condition      = var.github_repository_owner_id == null ? "" : " && assertion.repository_owner_id == '${var.github_repository_owner_id}'"

  project_role_bindings = {
    for pair in flatten([
      for env, roles in var.project_roles : [for role in roles : { env = env, role = role }]
    ]) : "${pair.env}/${pair.role}" => pair
  }
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Short-lived credentials for GitHub Actions in ${var.github_repository}"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.environment"         = "assertion.environment"
  }

  # Tokens from any other repository are refused before any binding is even looked at.
  attribute_condition = "${local.repository_condition}${local.owner_condition}"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "deploy" {
  for_each = var.environments

  project      = var.project_id
  account_id   = "${var.service_account_prefix}-${each.key}"
  display_name = "GitHub deploy (${each.key})"
  description  = "Impersonated by GitHub Actions jobs of ${var.github_repository} in the ${each.key} environment"
}

# The exact subject GitHub puts in the token for a job in that environment, not a principalSet.
resource "google_service_account_iam_member" "github_environment" {
  for_each = var.environments

  service_account_id = google_service_account.deploy[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/repo:${var.github_repository}:environment:${each.key}"
}

# Nothing is granted on the project by default: give each environment only what its deploy needs.
resource "google_project_iam_member" "deploy" {
  for_each = local.project_role_bindings

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.deploy[each.value.env].email}"

  lifecycle {
    precondition {
      condition     = contains(var.environments, each.value.env)
      error_message = "project_roles has a key that is not in environments."
    }
  }
}
