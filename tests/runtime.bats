#!/usr/bin/env bats
#
# lib/runtime.sh — the dry-run plumbing every install script relies on, plus
# the state file that drives the menu's "✓ done" marker.

load test_helper

setup() {
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  source "$REPO_ROOT/lib/runtime.sh"
}

@test "fpi_run executes the command when not in dry-run" {
  FPI_DRY_RUN=0
  run fpi_run echo hello
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "fpi_run prints DRY: and skips execution in dry-run" {
  FPI_DRY_RUN=1
  local sentinel="$BATS_TEST_TMPDIR/sentinel"
  run fpi_run touch "$sentinel"
  [ "$status" -eq 0 ]
  [[ "$output" == DRY:* ]]
  [ ! -e "$sentinel" ]
}

@test "the sudo override prints DRY: sudo and returns 0 in dry-run" {
  FPI_DRY_RUN=1
  run sudo dnf install -y example-package
  [ "$status" -eq 0 ]
  [ "$output" = "DRY: sudo dnf install -y example-package" ]
}

@test "mark_done / is_done round-trip through the state file" {
  run is_done system_configuration
  [ "$status" -ne 0 ]
  mark_done system_configuration
  run is_done system_configuration
  [ "$status" -eq 0 ]
}
