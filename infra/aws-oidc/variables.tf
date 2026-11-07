variable "github_repository" {
  description = "Repository allowed to assume the roles, as owner/name (no wildcards)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use owner/name with letters, digits, '-', '_' or '.', and no wildcards."
  }
}

variable "environments" {
  description = "GitHub environments that get their own role. Production should be protected by a required reviewer."
  type        = set(string)
  default     = ["staging", "production"]

  validation {
    condition     = length(var.environments) > 0 && alltrue([for env in var.environments : can(regex("^[A-Za-z0-9_.-]+$", env))])
    error_message = "Environment names use letters, digits, '-', '_' or '.', and no wildcards."
  }
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set to false if this AWS account already has one."
  type        = bool
  default     = true
}

variable "role_name_prefix" {
  description = "Role names become <prefix>-<environment>."
  type        = string
  default     = "github-deploy"
}

variable "max_session_duration" {
  description = "Longest a deploy job keeps the credentials, in seconds (AWS allows 3600 to 43200)."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "AWS accepts 3600 to 43200 seconds."
  }
}

variable "policy_arns" {
  description = "Managed policy ARNs to attach, per environment. Empty by default: the roles can do nothing until you choose."
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue([
      for arn in flatten(values(var.policy_arns)) :
      can(regex("^arn:aws[a-z-]*:iam::(aws|[0-9]{12}):policy/", arn))
    ])
    error_message = "Each entry must be an IAM policy ARN."
  }

  validation {
    condition = !anytrue([
      for arn in flatten(values(var.policy_arns)) :
      can(regex(":policy/(AdministratorAccess|PowerUserAccess|IAMFullAccess)$", arn))
    ])
    error_message = "A deploy role must not get AdministratorAccess, PowerUserAccess or IAMFullAccess."
  }
}
