#!/usr/bin/env bats
#
# Parse-only checks. `bash -n` catches the most common form of drift — a
# script that no longer parses — without running a single command.

load test_helper

@test "run.sh parses cleanly" {
  run bash -n "$REPO_ROOT/run.sh"
  [ "$status" -eq 0 ]
}

@test "every lib/*.sh parses cleanly" {
  local f
  for f in "$REPO_ROOT"/lib/*.sh; do
    run bash -n "$f"
    [ "$status" -eq 0 ] || { echo "parse error in $f:"; echo "$output"; return 1; }
  done
}

@test "every scripts/*.sh parses cleanly" {
  local f
  for f in "$REPO_ROOT"/scripts/*.sh; do
    run bash -n "$f"
    [ "$status" -eq 0 ] || { echo "parse error in $f:"; echo "$output"; return 1; }
  done
}
