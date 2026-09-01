####################################################################
# providers.tf — two aliased oci providers, one per region
#
# Every module that touches a region-specific resource is passed one of
# these two aliases explicitly (providers = { oci = oci.ashburn } etc.);
# nothing relies on the default (unaliased) provider except the
# provider block itself, which the plugin requires to exist.
#
# No credentials are configured here. In the Tier-C author-only posture
# this repo runs in, `terraform init -backend=false` and `terraform
# validate` never contact OCI, and `terraform test` uses
# `mock_provider "oci" {}` (see terraform/tests/). A real `terraform
# plan` requires the operator's own `oci session authenticate` (or
# equivalent env vars) — never credentials committed to this repo.
####################################################################

provider "oci" {
  region = var.primary_region
}

provider "oci" {
  alias  = "ashburn"
  region = var.primary_region
}

provider "oci" {
  alias  = "phoenix"
  region = var.dr_region
}
