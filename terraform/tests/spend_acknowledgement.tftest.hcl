# A spend_acknowledgement phrase without a matching, non-empty
# spend_acknowledgement_duration must never unlock apply — even if the
# phrase text looks plausible on its own.
mock_provider "oci" {}

mock_provider "oci" {
  alias = "ashburn"
}

mock_provider "oci" {
  alias = "phoenix"
}

run "phrase_without_duration_is_rejected" {
  command = plan

  variables {
    unlock_apply                   = true
    spend_acknowledgement_duration = "" # no duration supplied
    spend_acknowledgement          = "I accept the estimated cost for "
  }

  assert {
    condition     = local.apply_unlocked == false
    error_message = "apply_unlocked must stay false when spend_acknowledgement_duration is empty, regardless of spend_acknowledgement text."
  }

  expect_failures = [
    terraform_data.apply_lock_guard,
    check.apply_lock_posture,
  ]
}

run "phrase_with_wrong_duration_is_rejected" {
  command = plan

  variables {
    unlock_apply                   = true
    spend_acknowledgement_duration = "8h"
    # References a different duration than the one declared above —
    # a stale or copy-pasted acknowledgement must not match.
    spend_acknowledgement = "I accept the estimated cost for 24h"
  }

  assert {
    condition     = local.apply_unlocked == false
    error_message = "apply_unlocked must stay false when the acknowledgement phrase's duration does not match spend_acknowledgement_duration."
  }

  expect_failures = [
    terraform_data.apply_lock_guard,
    check.apply_lock_posture,
  ]
}

run "malformed_duration_is_rejected_by_variable_validation" {
  command = plan

  variables {
    unlock_apply                   = true
    spend_acknowledgement_duration = "8" # missing the required h|d suffix
    spend_acknowledgement          = "I accept the estimated cost for 8"
  }

  expect_failures = [
    var.spend_acknowledgement_duration,
  ]
}

run "correct_phrase_and_duration_unlocks" {
  command = plan

  variables {
    unlock_apply                   = true
    spend_acknowledgement_duration = "8h"
    spend_acknowledgement          = "I accept the estimated cost for 8h"
  }

  assert {
    condition     = local.apply_unlocked == true
    error_message = "a correctly matching phrase + duration must unlock apply."
  }
}
