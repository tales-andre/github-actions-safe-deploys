variable "project_id" {
  description = "Google Cloud project that holds the pool and the deploy service accounts."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Not a valid project ID."
  }
}

variable "github_repository" {
  description = "Repository allowed to use the pool, as owner/name (no wildcards)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use owner/name with letters, digits, '-', '_' or '.', and no wildcards."
  }
}

variable "github_repository_owner_id" {
  description = "Optional numeric ID of the repository owner. Also checking it keeps working if someone later takes over the owner's old name."
  type        = string
  default     = null

  validation {
    condition     = var.github_repository_owner_id == null || can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "The owner ID is a number, as shown by the GitHub API."
  }
}

variable "environments" {
  description = "GitHub environments that get their own service account. Production should be protected by a required reviewer."
  type        = set(string)
  default     = ["staging", "production"]

  validation {
    condition     = length(var.environments) > 0 && alltrue([for env in var.environments : can(regex("^[a-z0-9-]{1,14}$", env))])
    error_message = "Environment names here use lowercase letters, digits or '-', up to 14 characters (they become part of a service account ID)."
  }
}

variable "pool_id" {
  description = "Workload Identity pool ID."
  type        = string
  default     = "github"
}

variable "service_account_prefix" {
  description = "Service account IDs become <prefix>-<environment>."
  type        = string
  default     = "gh-deploy"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,14}$", var.service_account_prefix))
    error_message = "Use 5 to 15 lowercase letters, digits or '-', starting with a letter."
  }
}

variable "project_roles" {
  description = "Project roles to grant, per environment. Empty by default: the service accounts can do nothing until you choose."
  type        = map(list(string))
  default     = {}

  validation {
    condition = !anytrue([
      for role in flatten(values(var.project_roles)) :
      contains(["roles/owner", "roles/editor", "roles/iam.securityAdmin", "roles/iam.serviceAccountKeyAdmin"], role)
    ])
    error_message = "A deploy service account must not get owner, editor, security admin or key admin."
  }
}
