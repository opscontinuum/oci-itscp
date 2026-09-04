# terraform/ — OCI Terraform for the EBS DR environment

This is a **Tier-C, author-only, never-apply** Terraform configuration for the
worked example described in the repository root [`README.md`](../README.md)
and [`docs/01-architecture.md`](../docs/01-architecture.md). It has never
been applied against a real OCI tenancy — there is no live environment behind it,
no real OCIDs, and no state file in this repository.

If you are building a real plan from this repo, see the root README's
["If you are building a real plan from this"](../README.md#if-you-are-building-a-real-plan-from-this)
section first, and read "Apply lock" below before you touch `unlock_apply`.

## Apply lock

Every resource in every module is gated on one root local value,
`local.apply_unlocked`, computed in [`variables.tf`](variables.tf):

```hcl
locals {
  required_spend_phrase = "I accept the estimated cost for ${var.spend_acknowledgement_duration}"

  apply_unlocked = (
    var.unlock_apply &&
    var.spend_acknowledgement_duration != "" &&
    var.spend_acknowledgement == local.required_spend_phrase
  )
}
```

By default (`unlock_apply = false`), `local.apply_unlocked` is `false` and
**every resource in this configuration plans to `count = 0` or
`for_each = {}`.** `terraform plan` against this repo's defaults, with real
credentials, would create nothing.

To unlock apply, you must set **three** variables together:

| Variable | Example | Purpose |
|---|---|---|
| `unlock_apply` | `true` | The on/off switch |
| `spend_acknowledgement_duration` | `"8h"` | How long you accept the estimated spend for — must match `^[0-9]+(h\|d)$` |
| `spend_acknowledgement` | `"I accept the estimated cost for 8h"` | Must equal **exactly** `"I accept the estimated cost for <spend_acknowledgement_duration>"` |

Run `make smoke-8h` (or `terraform output bom`, once you've applied against
your own tenancy) to see the Bill of Materials before typing that phrase for
real — it is a deliberate typed acknowledgement, not a rubber stamp.

**Enforcement is two-layered:**

1. **`terraform_data.apply_lock_guard`** (`main.tf`) — a built-in resource
   (`terraform.io/builtin/terraform`, no OCI credentials needed) with a
   `lifecycle.precondition`. Its condition is
   `!var.unlock_apply || local.apply_unlocked`: trivially true in the
   default LOCKED state (that's the point — `validate`/`test` must pass
   against the safe default), and it **fails loudly, with the reason**, only
   if someone sets `unlock_apply = true` without also supplying the exact
   matching phrase — an attempted-but-incomplete unlock.
2. **`check "apply_lock_posture"`** (`main.tf`) — the same condition,
   expressed as a top-level `check` block. `terraform plan`/`apply` treat a
   failed `check` assertion as a non-blocking warning by design (since
   Terraform 1.5); `terraform test` treats it as a run failure, which is why
   `tests/locked.tftest.hcl` and `tests/spend_acknowledgement.tftest.hcl`
   both list `check.apply_lock_posture` in their `expect_failures` for the
   misconfigured-unlock scenarios.

A **real** `terraform plan` against your own tenancy additionally requires
your own `oci session authenticate` (or equivalent OCI CLI/SDK credentials).
Nothing in this repository configures, stores, or expects credentials —
`providers.tf` declares three `provider "oci"` blocks (default + `ashburn`/
`phoenix` aliases) with only `region` set.

## Layout

```
terraform/
  providers.tf        two aliased oci providers (ashburn, phoenix) + default
  versions.tf          Terraform >= 1.7.0 (check blocks, terraform test), oracle/oci >= 6.0.0
  variables.tf          apply lock, regions, compartment, AD placeholders, tier/posture selectors
  main.tf                apply-lock guard, node topology, module composition
  outputs.tf             apply_lock_status, BOM, per-module pass-throughs
  Makefile                init / fmt-check / validate / test / smoke-8h / plan / apply / teardown
  dr-resources.env.example   (pre-existing — populated by hand from `terraform output` post-build)
  modules/
    network/     VCNs, per-AD app subnets, db+backup subnets, public lb subnets,
                 DRG + Remote Peering Connection, NSGs, private DNS view+zone per region
    compute/     Windows non-moving instances, EBS data volumes in a volume group with
                 cross-region replication, Oracle Cloud Agent Run Command plugin
    storage/     File Storage (+ replication), Object Storage interchange buckets
                 (+ replication policy), FSDR log buckets (Standard, no replication)
    lb/          Flexible load balancer per region + WAF policy/attachment
    dns/         Traffic Management FAILOVER steering policy + Health Checks
    database/    database_tier = "exadb-d" | "basedb" (see below)
    recovery/    Autonomous Recovery Service: protection policy + protected database (primary only)
    fsdr/        DR Protection Group peer pair + 4 DR plans (switchover/failover/start_drill/stop_drill)
    monitoring/  Notification topic + 6 alarms (docs/04-monitoring.md §2 namespaces/metrics)
    scheduler/   WARM-posture stop schedule, excludes the always-on BI node
  tests/
    locked.tftest.hcl              default posture: everything count 0; misconfigured unlock fails loudly
    unlocked.tftest.hcl            expected resource shape for both database_tier values
    spend_acknowledgement.tftest.hcl   phrase/duration matching edge cases
```

## database_tier

`var.database_tier` selects between two mutually exclusive resource sets in
`modules/database`:

- **`"exadb-d"` (default)** — `oci_database_cloud_exadata_infrastructure` +
  `oci_database_cloud_vm_cluster`, one pair per region. This is the plan's
  actual documented design (`docs/01-architecture.md` A2). `cpu_core_count`
  lives on the VM cluster (not the Exadata infrastructure resource) and is
  bounded below by a `>= 2 OCPU per node` variable validation on both
  `ashburn_cpu_core_count` and `phoenix_cpu_core_count` — the Phoenix floor
  specifically guards against `docs/05-cost-and-teardown.md` §2's warning
  that scaling to 0 OCPU shuts the whole VM cluster down and silently
  converts Tier 1 into Tier 3.
- **`"basedb"`** — the Tier-C cheap alternative used for the OCI Cost
  Estimator BOM: `oci_database_db_system` (1-node, BYOL by default via
  `license_model = "BRING_YOUR_OWN_LICENSE"`) plus
  `oci_database_data_guard_association` (`creation_type = "NewDbSystem"`)
  for the Phoenix standby.

  **Caveat, read before using this tier for anything beyond the BOM:**
  neither `oci_database_data_guard_association`'s Terraform Registry page
  nor `oci_database_database`'s `source = "DATAGUARD"` path documents an
  explicit cross-region/peer-region argument for standby placement (both
  pages were grepped in full for "region" — no cross-region
  standby-placement field on either). Whether a classic Data Guard
  Association can place the standby in a different region's subnet than the
  primary was **not confirmed** in this revision. This is exactly the gap
  `docs/01-architecture.md` A2 designs around by requiring ExaDB-D, whose
  cross-region standby path is the one Oracle's own documentation describes
  (`docs/01-architecture.md` §3, `docs/03-replication-matrix.md` R1).
  Validate against the OCI Database API reference and a real tenancy before
  relying on cross-region `basedb` Data Guard for anything operational.

  A second, narrower gap: the `basedb` tier resolves its primary database's
  OCID through two chained data sources
  (`oci_database_db_homes` → `oci_database_databases`), since
  `oci_database_db_system` exposes no top-level `db_home_id`/`database_id`
  computed attribute. The `exadb-d` tier does **not** provision an actual
  pluggable/container database on the Exadata VM cluster at all — Oracle's
  EBS clone process creates it via DBCA/RMAN duplicate against the cluster
  (`runbooks/RB-05-replication-lifecycle.md` Phase 2/4), not a first-class
  Terraform resource — so `modules/fsdr`'s `DATABASE` member is only wired
  automatically for the `basedb` tier; for `exadb-d`, supply the database
  OCID out-of-band via `dr-resources.env`'s `PRIMARY_DATABASE_OCID` and add
  the member manually (commented in `main.tf`'s `module "fsdr"` block).

## Placeholders and caveats

No `null_resource` placeholder was needed anywhere — every resource named in
the brief has a real, current `oracle/oci` provider resource type, including
the WAF (`oci_waf_web_app_firewall` + `oci_waf_web_app_firewall_policy`) and
the FSDR `DATABASE` member type (present in the `oracle/oci-go-sdk` enum
source even though the Terraform Registry markdown's own prose doesn't spell
it out explicitly — see `modules/fsdr/main.tf`'s header comment). What *is*
intentionally minimal:

- **`modules/lb`'s WAF policies** (`oci_waf_web_app_firewall_policy`) are
  created with zero rules — a real, valid, empty policy. Real WAF rule
  content is business logic specific to the EBS environment and does not belong
  hard-coded in a public worked example; that emptiness is the "WAF
  placeholder" the brief asked for, expressed through a genuine resource
  rather than an inert stand-in.
- **`modules/dns`'s FAILOVER steering policy** rule shape (`FILTER` →
  `HEALTH` → `PRIORITY` → `LIMIT`, as the `FAILOVER` template requires) is
  correct per the schema, but the exact `PRIORITY`-rule `answer_condition`
  combination that reliably ranks one pool ahead of another beyond a single
  `default_answer_data` block was not spelled out in a full worked example
  on the provider docs page. Validate the rendered policy in the OCI
  console against a real health check before relying on it operationally.
- **`modules/compute`'s Run Command plugin name** (`"Compute Instance Run
  Command"`) is documented only in prose on the `oci_core_instance` registry
  page ("These are the management plugins: OS Management Service Agent and
  Compute Instance Run Command"), not as a literal `name =` example.
  Confirm the exact string with
  `oci compute-instance-agent instance-available-plugin list` against a real
  tenancy before ever applying this.
- **`modules/monitoring`'s alarm queries** use the exact namespaces/metrics
  from `docs/04-monitoring.md` §2 (`oracle_oci_database` `ApplyLag`/
  `TransportLag`, `oci_blockstore` `VolumeReplicationSecondsSinceLastSync`,
  `oci_filestorage` `ReplicationRecoveryPointAge`, `oci_database_cluster`
  `OcpusAllocated`) at the CRITICAL threshold only; add a second
  WARNING-severity alarm per row if you want that threshold to page
  separately too.
- **`modules/network`'s Phoenix AD count** defaults to a single AD
  (`phoenix_app_subnets` has one entry, `ad1`) — confirm the actual AD count
  for `us-phoenix-1` in your own tenancy before relying on this.
- **Availability domain names** (`ashburn_ad1`/`ashburn_ad2`/`phoenix_ad1` in
  root `variables.tf`) default to placeholder strings (`"AD-1"`, `"AD-2"`).
  Real OCI AD names are tenancy-specific
  (e.g. `"kIdl:US-ASHBURN-1-AD-1"`) — look yours up with
  `oci iam availability-domain list` before ever applying.

## Provider documentation read

Every resource type below was verified against its Terraform Registry page
(`https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/<name>`)
by fetching the provider's own canonical Markdown source
(`github.com/oracle/terraform-provider-oci`, `website/docs/r/<name>.html.markdown`,
`master` branch — the Registry site itself is a JS SPA that a plain fetch
cannot render, so the Markdown that renders each Registry page was read
directly instead). Where the Terraform Registry markdown did not spell out
an enum's allowed values in prose (`oci_disaster_recovery_dr_plan.type`,
`oci_disaster_recovery_dr_protection_group.association.role` and
`.members.member_type`, `oci_resource_scheduler_schedule.action`/
`.recurrence_type`), the enum was additionally confirmed against the
generated Go SDK source (`github.com/oracle/oci-go-sdk`, matching the
published OCI API) — cited inline in each module's header comment.

Resources read: `oci_core_vcn`, `oci_core_subnet`, `oci_core_internet_gateway`,
`oci_core_route_table`, `oci_core_drg`, `oci_core_drg_attachment`,
`oci_core_remote_peering_connection`, `oci_core_network_security_group`,
`oci_core_network_security_group_security_rule`, `oci_dns_view`,
`oci_dns_zone`, `oci_core_instance`, `oci_core_volume`,
`oci_core_volume_group`, `oci_core_volume_attachment`, `oci_core_boot_volume`,
`oci_file_storage_file_system`, `oci_file_storage_mount_target`,
`oci_file_storage_export`, `oci_file_storage_export_set`,
`oci_file_storage_replication`, `oci_objectstorage_bucket`,
`oci_objectstorage_replication_policy`, `oci_load_balancer_load_balancer`,
`oci_load_balancer_backend_set`, `oci_load_balancer_backend`,
`oci_load_balancer_listener`, `oci_waf_web_app_firewall`,
`oci_waf_web_app_firewall_policy`, `oci_dns_steering_policy`,
`oci_dns_steering_policy_attachment`, `oci_health_checks_http_monitor`,
`oci_database_cloud_exadata_infrastructure`, `oci_database_cloud_vm_cluster`,
`oci_database_db_system`, `oci_database_data_guard_association`,
`oci_database_database`, `data.oci_database_db_homes`,
`data.oci_database_databases`, `oci_recovery_recovery_service_subnet`,
`oci_recovery_protection_policy`, `oci_recovery_protected_database`,
`oci_disaster_recovery_dr_protection_group`, `oci_disaster_recovery_dr_plan`,
`oci_ons_notification_topic`, `oci_monitoring_alarm`,
`oci_resource_scheduler_schedule`.

## Verification

```
make init          # terraform init -backend=false — no credentials
make fmt-check      # terraform fmt -recursive -check
make validate        # terraform validate — no credentials
make test              # terraform test, mock_provider "oci" {} — no credentials
make smoke-8h            # prints the BOM + exact 8h spend-override phrase; never applies
```

All four (`init`, `fmt-check`, `validate`, `test`) pass against this
revision. `plan`, `apply`, and `teardown` are documented in the `Makefile`
but never executed by anything in this repository — they require your own
OCI credentials and a deliberate apply-lock release.
