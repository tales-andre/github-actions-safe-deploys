output "role_arns" {
  description = "Role ARN per environment. Store each one as the AWS_ROLE_ARN variable of the matching GitHub environment."
  value       = { for env, role in aws_iam_role.deploy : env => role.arn }
}

output "oidc_provider_arn" {
  description = "The GitHub OIDC provider the roles trust."
  value       = local.oidc_provider_arn
}
