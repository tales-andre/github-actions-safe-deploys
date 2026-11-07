# infra/ is only the root for `terraform test` (tests/*.tftest.hcl): it pins the provider
# versions the tests use and creates nothing. Apply each module from its own folder,
# aws-oidc/ or gcp-wif/, in your own account (see the README).

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}
