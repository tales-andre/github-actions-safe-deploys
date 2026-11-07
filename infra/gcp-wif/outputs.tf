output "workload_identity_provider" {
  description = "Full provider name. Store it as the GCP_WORKLOAD_IDENTITY_PROVIDER repository variable."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_emails" {
  description = "Service account per environment. Store each one as the GCP_SERVICE_ACCOUNT variable of the matching GitHub environment."
  value       = { for env, sa in google_service_account.deploy : env => sa.email }
}
