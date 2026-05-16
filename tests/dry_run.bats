#!/usr/bin/env bats
#
# Dry-run smoke tests. Each script is run with FPI_DRY_RUN=1 so the
# lib/runtime.sh sudo override prints every privileged call as `DRY: …`
# instead of executing it. This catches strict-mode regressions (an
# unguarded `set -e`/`pipefail` exit) and DNF syntax drift across Fedora
# releases without mutating the host.
#
# Only scripts that are network-free under dry-run are asserted here.
# packages_installation / development_installation / configure_secureboot
# perform non-sudo downloads or key generation that dry-run does not
# intercept, so they get parse-only coverage in syntax.bats instead.

load test_helper

@test "system_configuration.sh dry-run completes and emits DRY dnf calls" {
  run env FPI_DRY_RUN=1 FPI_DEFER_REBOOT=1 \
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" \
    bash "$REPO_ROOT/scripts/system_configuration.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY: sudo dnf"* ]]
  [[ "$output" != *"unbound variable"* ]]
  [[ "$output" != *"command not found"* ]]
}

@test "virtualization_installation.sh dry-run does not crash" {
  run env FPI_DRY_RUN=1 FPI_DEFER_REBOOT=1 \
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" \
    bash "$REPO_ROOT/scripts/virtualization_installation.sh"
  # Exits 0 on a virt-capable CPU, or 1 with a clear message otherwise.
  # Both outcomes are fine — a bash-level error is not.
  [[ "$status" -eq 0 || "$output" == *"CPU does not support"* ]]
  [[ "$output" != *"unbound variable"* ]]
}

@test "nvidia_drivers.sh dry-run does not crash" {
  run env FPI_DRY_RUN=1 FPI_DEFER_REBOOT=1 \
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" \
    bash "$REPO_ROOT/scripts/nvidia_drivers.sh"
  # Exits 0 when an NVIDIA GPU is present, or 1 with a clear message when
  # not. Both outcomes are fine — a bash-level error is not.
  [[ "$status" -eq 0 || "$output" == *"No NVIDIA GPU detected"* ]]
  [[ "$output" != *"unbound variable"* ]]
}
