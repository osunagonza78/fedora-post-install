#!/bin/bash

# =============================================================================
# RUNTIME LIBRARY
# =============================================================================
# Shared runtime helpers used by run.sh and (optionally) scripts/*:
#   - XDG-style state and log directory paths
#   - mark_done / is_done / list_done for the menu's "✓ done" marker
#   - mark_reboot_needed for the single deferred-reboot prompt
#   - fpi_run wrapper that honours $FPI_DRY_RUN
#
# Sourced by run.sh and by anything in scripts/ that wants dry-run/state.
# Pure shell, no `set -e` (caller's strictness governs).
# =============================================================================

# Anchor paths under XDG_STATE_HOME with a sane default. The state file is
# the only persistent surface this tool writes outside of /opt and /etc.
FPI_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fpi"
FPI_LOG_DIR="${FPI_STATE_DIR}/logs"
FPI_DONE_FILE="${FPI_STATE_DIR}/done"
FPI_REBOOT_MARKER="${FPI_STATE_DIR}/needs_reboot"

fpi_ensure_state_dirs() {
    mkdir -p "$FPI_LOG_DIR" 2>/dev/null
}

# Mark a script as completed. Format: one "<script-basename>|<ISO timestamp>"
# line per run. Re-runs append; latest line wins for is_done's purposes.
mark_done() {
    local script_name="$1"
    fpi_ensure_state_dirs
    printf '%s|%s\n' "$script_name" "$(date -Is)" >> "$FPI_DONE_FILE"
}

# True if the named script appears in the done file.
is_done() {
    local script_name="$1"
    [[ -f "$FPI_DONE_FILE" ]] && grep -q "^${script_name}|" "$FPI_DONE_FILE"
}

# Emit "yes" if name in done file, "no" otherwise. Used by the menu painter.
done_marker() {
    local script_name="$1"
    if is_done "$script_name"; then
        echo "yes"
    else
        echo "no"
    fi
}

# Flag that *some* script in this session needs a reboot. run.sh checks this
# marker on exit and prompts once instead of each script prompting.
mark_reboot_needed() {
    local reason="${1:-Pending changes require a reboot.}"
    fpi_ensure_state_dirs
    printf '%s\n' "$reason" >> "$FPI_REBOOT_MARKER"
}

reboot_needed() {
    [[ -f "$FPI_REBOOT_MARKER" ]]
}

clear_reboot_marker() {
    rm -f "$FPI_REBOOT_MARKER"
}

# Wrap a command for dry-run support. When FPI_DRY_RUN=1, prints the command
# prefixed with "DRY:" and skips execution. Otherwise runs it normally.
# Use for any side-effecting command (sudo dnf, sudo systemctl, sudo install,
# wget, etc.) you want to be safe under --dry-run.
fpi_run() {
    if [[ "${FPI_DRY_RUN:-0}" = "1" ]]; then
        printf 'DRY: %s\n' "$*"
        return 0
    fi
    "$@"
}

# Dry-run sudo override.
#
# When FPI_DRY_RUN=1, every `sudo …` call from any script that sources this
# library is intercepted: we print the command prefixed with "DRY:" and
# return 0 instead of executing. All side-effecting calls in this codebase
# (`dnf install`, `systemctl enable`, `install -m`, `tee /etc/...`,
# `mokutil --import`, `kmodgenca`, `dnf config-manager …`) go through
# sudo, so this single override catches the whole transaction.
#
# Non-sudo commands (wget, unzip, fc-cache, mkdir under $HOME) are *not*
# intercepted — they're idempotent or user-scoped, and the improvements
# brief framed dry-run as "the dnf transaction".
#
# Bypass the override (e.g. to actually prime sudo creds in preflight) with
# `command sudo …`, which skips functions.
sudo() {
    if [[ "${FPI_DRY_RUN:-0}" = "1" ]]; then
        printf 'DRY: sudo %s\n' "$*"
        return 0
    fi
    command sudo "$@"
}
