####################################################################
# versions.tf — Terraform and provider version constraints
#
# Tier-C "author only, never apply" posture: this repository never runs
# `terraform plan` or `terraform apply` against a real OCI tenancy (see
# README.md "Apply lock" and the root README's "Status" section). The
# version floor below is chosen for `check` block / `terraform test`
# support (Terraform >= 1.7) and current oracle/oci resource coverage,
# not because anything here has been applied against those versions.
####################################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0"
    }
  }
}
