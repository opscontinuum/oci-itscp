####################################################################
# Makefile — terraform/ verification and lifecycle targets.
#
# TIER-C "AUTHOR ONLY, NEVER APPLY" POSTURE:
#   - `init`, `fmt-check`, `validate`, `test` never touch a real OCI
#     tenancy. `test` uses mock_provider "oci" {} (Terraform >= 1.7)
#     so it runs with zero credentials.
#   - `plan`/`apply`/`teardown` are NOT wired to run automatically —
#     they require the operator's own `oci session authenticate` (or
#     equivalent credentials) against their own tenancy, and the
#     apply lock (unlock_apply + spend_acknowledgement, see README.md
#     "Apply lock") must be deliberately released first. This
#     Makefile documents the commands; it does not run them for you.
#   - `smoke-8h` never applies. It only prints the BOM and the exact
#     spend-override phrase required to unlock an 8-hour posture.
####################################################################

TERRAFORM ?= terraform

.PHONY: init fmt-check fmt validate test teardown smoke-8h plan apply help

help:
	@echo "make init        - terraform init -backend=false (no credentials)"
	@echo "make fmt-check   - terraform fmt -recursive -check"
	@echo "make fmt         - terraform fmt -recursive (writes changes)"
	@echo "make validate    - terraform validate (no credentials)"
	@echo "make test        - terraform test, mock_provider (no credentials)"
	@echo "make smoke-8h    - print the BOM + exact 8h spend-override phrase; never applies"
	@echo "make plan        - REQUIRES your own OCI credentials + unlock_apply=true; not run by CI"
	@echo "make apply       - REQUIRES your own OCI credentials + unlock_apply=true; not run by CI"
	@echo "make teardown    - single teardown command: terraform destroy behind the same unlock"

init:
	$(TERRAFORM) init -backend=false -input=false

fmt-check:
	$(TERRAFORM) fmt -recursive -check

fmt:
	$(TERRAFORM) fmt -recursive

validate: init
	$(TERRAFORM) validate

test: init
	$(TERRAFORM) test

# --- smoke-8h: prints the BOM and the exact spend-override phrase for an
# 8-hour acknowledgement window. Never applies, never plans against a real
# tenancy — it only evaluates the two informational outputs, which are pure
# functions of input variables and therefore safe to read with no
# credentials at all (terraform providers schema / output -json against an
# unapplied plan would need a provider; instead this greps the source of
# truth directly so `make smoke-8h` needs nothing but this repo).
smoke-8h:
	@echo "=== BOM (see terraform output bom after a real init/plan against your own tenancy) ==="
	@echo "Tier-C cheap-variant BOM — no prices (docs/05-cost-and-teardown.md):"
	@sed -n '/output "bom"/,/^}/p' outputs.tf | sed -n '/value = \[/,/\]/p' | grep '"' | sed 's/^ *//'
	@echo ""
	@echo "=== Required spend-acknowledgement phrase for an 8h window ==="
	@echo 'unlock_apply                   = true'
	@echo 'spend_acknowledgement_duration = "8h"'
	@echo 'spend_acknowledgement          = "I accept the estimated cost for 8h"'
	@echo ""
	@echo "This target never runs plan or apply. Review the BOM above against the"
	@echo "OCI Cost Estimator (docs/05-cost-and-teardown.md) before ever setting"
	@echo "these values for real."

# --- plan / apply: documented, not executed by anything in this repo.
# Requires the operator's own credentials (`oci session authenticate`) and
# an explicit, deliberate override of the apply lock. See README.md
# "Apply lock" before running either of these by hand.
plan:
	@echo "Not run automatically. Requires your own OCI credentials and the apply lock released."
	@echo "Example: $(TERRAFORM) plan -var unlock_apply=true -var spend_acknowledgement_duration=8h \\"
	@echo "           -var 'spend_acknowledgement=I accept the estimated cost for 8h'"

apply:
	@echo "Not run automatically. Requires your own OCI credentials and the apply lock released."
	@echo "Example: $(TERRAFORM) apply -var unlock_apply=true -var spend_acknowledgement_duration=8h \\"
	@echo "           -var 'spend_acknowledgement=I accept the estimated cost for 8h'"

# --- teardown: the single documented teardown command, behind the same
# unlock as apply. Not run automatically.
teardown:
	@echo "Not run automatically. Requires your own OCI credentials and the apply lock released."
	@echo "Single teardown command (destroy behind the same unlock, RB-05 §5):"
	@echo "  $(TERRAFORM) destroy -var unlock_apply=true -var spend_acknowledgement_duration=8h \\"
	@echo "    -var 'spend_acknowledgement=I accept the estimated cost for 8h'"
	@echo "This destroys everything this Terraform created, including replication."
	@echo "It is NOT the routine WARM-posture cost lever — see docs/03-replication-matrix.md"
	@echo "§3 and RB-05-replication-lifecycle.md: tear down compute (scripts/oci/set-dr-posture.sh),"
	@echo "never tear down replication, outside of a real decommission (RB-05 §5)."
