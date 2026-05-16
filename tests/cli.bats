#!/usr/bin/env bats
#
# run.sh's non-interactive CLI contract. None of these enter tmux or touch
# the network — they exercise the flag parser and its exit codes only.

load test_helper

@test "--help prints usage and exits 0" {
  run bash "$REPO_ROOT/run.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "--list prints the script keys and exits 0" {
  run bash "$REPO_ROOT/run.sh" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"system_configuration"* ]]
  [[ "$output" == *"nvidia_drivers"* ]]
}

@test "an unknown flag exits 2" {
  run bash "$REPO_ROOT/run.sh" --not-a-real-flag
  [ "$status" -eq 2 ]
}

@test "--run with no key exits 2" {
  run bash "$REPO_ROOT/run.sh" --run
  [ "$status" -eq 2 ]
}
