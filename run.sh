#!/bin/bash

# =============================================================================
# Fedora Post-Installation Tool
# =============================================================================
# A comprehensive post-installation configuration tool for Fedora Linux that
# automates system setup, package installation, driver configuration, and
# security settings through an interactive menu interface.
#
# Copyright (C) 2025 Gilberto Osuna Gonzalez
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Author: Gilberto Osuna Gonzalez
# Version: 1.0
# License: GPL v3.0
# Repository: https://github.com/gosuna78/fedora-post-install
# =============================================================================

# Colour palette comes from lib/ui.sh, sourced below alongside the other libs.

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/"

# --- Hard precondition: this only runs on Fedora 41+ ---
# Sourced here (not inside main_loop) so the guard fires before tmux exec.
# require_fedora itself exits 1 if /etc/fedora-release is missing or the
# version is older than 41 — see lib/verify.sh.
# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}lib/logging.sh"
# shellcheck source=lib/verify.sh
source "${SCRIPT_DIR}lib/verify.sh"
# shellcheck source=lib/runtime.sh
source "${SCRIPT_DIR}lib/runtime.sh"
require_fedora

# --- CLI parsing (--help, --list, --run KEY, --dry-run) ---
# Parsed before the tmux exec so headless callers never enter tmux. The
# non-interactive --run path skips the menu entirely; the interactive path
# falls through to the tmux relaunch + menu below.
FPI_RUN_TARGET=""
FPI_NONINTERACTIVE=""

cli_usage() {
    cat <<'USAGE'
Usage:
  ./run.sh                       Launch interactive menu (default)
  ./run.sh --list                List available script keys and exit
  ./run.sh --run KEY             Run one script non-interactively (no tmux)
  ./run.sh --run all             Run the recommended baseline non-interactively
  ./run.sh --dry-run [--run KEY] Print dnf transactions instead of applying
  ./run.sh --help                Show this help and exit

KEY is the basename of a script in scripts/ without the .sh suffix
(e.g. system_configuration, packages_installation, nvidia_drivers).
USAGE
}

cli_list() {
    # MENU_ITEMS is the source of truth — declared later in this file.
    # Re-source ourselves with a stub to get at it without launching tmux.
    echo "Available script keys:"
    local item key
    for item in "${MENU_ITEMS[@]}"; do
        key="${item%%|*}"
        [[ "$key" =~ ^_ ]] && continue
        echo "  $key"
    done
    echo
    echo "Special:"
    echo "  all   — chains system_configuration + packages_installation"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            # MENU_ITEMS isn't declared until later, but cli_usage doesn't
            # reference it — safe to call here. cli_list does need it; we
            # handle --list after MENU_ITEMS is declared, below.
            cli_usage
            exit 0
            ;;
        --list)
            FPI_NONINTERACTIVE=1
            FPI_RUN_TARGET="__list__"
            shift
            ;;
        --run)
            FPI_NONINTERACTIVE=1
            FPI_RUN_TARGET="${2:-}"
            if [[ -z "$FPI_RUN_TARGET" ]]; then
                echo "Error: --run requires a KEY argument (or 'all')" >&2
                cli_usage >&2
                exit 2
            fi
            shift 2
            ;;
        --dry-run)
            export FPI_DRY_RUN=1
            shift
            ;;
        *)
            echo "Error: unknown flag: $1" >&2
            cli_usage >&2
            exit 2
            ;;
    esac
done

# --- Auto-launch in tmux for split-pane view ---
# We run on a dedicated tmux socket so our keybindings, styling, and
# kill-server-on-exit don't leak into the user's main tmux config.
# Skipped when --run / --list put us in non-interactive mode — those paths
# don't need (or want) a split-pane TUI.
FPI_TMUX_SOCKET="fpi-postinstall"
if [[ -z "$FPI_NONINTERACTIVE" ]] && command -v tmux &>/dev/null && [[ -z "$TMUX" ]]; then
    exec tmux -L "$FPI_TMUX_SOCKET" new-session "bash \"${SCRIPT_DIR}run.sh\""
fi

# --- One-time tmux configuration + pane layout ---
# Configure ergonomic bindings/styling on this dedicated server, then spawn the
# persistent right-side output pane.  The pane stays alive for the whole
# session and is reused for every operation so the layout never flashes.
if [[ -z "$FPI_NONINTERACTIVE" && -n "$TMUX" && -z "$FPI_OUTPUT_PANE" ]]; then
    # Pane navigation: Alt+arrows move focus, mouse clicks focus a pane.
    tmux bind-key -n M-Left  select-pane -L
    tmux bind-key -n M-Right select-pane -R
    tmux set-option -g mouse on
    tmux set-option -g status off
    tmux set-window-option -g pane-border-style        'fg=colour240'
    tmux set-window-option -g pane-active-border-style 'fg=colour39,bold'

    FPI_MENU_PANE=$(tmux display-message -p '#{pane_id}')
    FPI_OUTPUT_PANE=$(tmux split-window -h -l 55% -P -F '#{pane_id}' -d \
        "bash '${SCRIPT_DIR}lib/output_pane.sh' idle")
    export FPI_MENU_PANE FPI_OUTPUT_PANE
fi

# --- Menu Items ---
# Single source of truth used by show_menu(), main_loop(), and --list.
# Format: "key|Display Text|Description"
#
# `key` matches the script basename in scripts/ (without .sh), or starts with
# "_" for synthetic entries that don't map to a single script. The state file
# uses these same keys to render the ✓ marker for completed scripts.
MENU_ITEMS=(
    "system_configuration|System Configuration|Optimize DNF, set hostname, and tune system limits."
    "packages_installation|Packages Installation|Enable RPM Fusion, Flatpak, and install essential apps."
    "development_installation|Development Environment Installation|Install Development Tools."
    "virtualization_installation|Virtualization Stack|Install KVM/QEMU hypervisor and libvirt services."
    "configure_secureboot|Secure Boot Config|Generate and enroll MOK keys for 3rd party modules."
    "nvidia_drivers|Nvidia Drivers|Install latest proprietary drivers via Akmod."
    "_baseline|Run Recommended Baseline|System Configuration + Packages Installation back-to-back."
    "_exit|Exit|"
)

# Baseline = scripts the baseline-run option chains. Keep small and
# hardware-agnostic; users add the rest by individual menu choices.
BASELINE_KEYS=(system_configuration packages_installation)

# --- CLI exit paths that need MENU_ITEMS ---
# Process --list now that MENU_ITEMS is declared. --run is handled lower
# (after run_script and the baseline runner are defined).
if [[ "$FPI_RUN_TARGET" == "__list__" ]]; then
    cli_list
    exit 0
fi

# =============================================================================
# FUNCTIONS
# =============================================================================

# Display the application header and title
# Creates a clean, branded interface showing the tool name and purpose
# Usage: show_header
show_header() {
    clear
    echo -e "${BANNER}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${BANNER}│${NC}             ${BOLD}FEDORA POST-INSTALL TOOL${NC}               ${BANNER}│${NC}"
    echo -e "${BANNER}╰──────────────────────────────────────────────────────────╯${NC}"
    echo ""
}

# Background updater that keeps the menu pane fresh while the right pane runs
# a script. Re-renders every 2s with elapsed time + last log line so the user
# has a heartbeat instead of a frozen placeholder.
#
# Used by run_script: forked before tmux wait-for, killed after.
show_running_state_live() {
    local title="$1"
    local script_basename="$2"
    local start_time
    start_time=$(date +%s)
    while sleep 2; do
        local elapsed=$(( $(date +%s) - start_time ))
        local mins=$((elapsed / 60))
        local secs=$((elapsed % 60))

        # The freshest log for this script — output_pane.sh creates one per
        # invocation timestamped to the second.
        local logfile last_line=""
        # shellcheck disable=SC2012  # log filenames are timestamped, not user input
        logfile=$(ls -t "${FPI_LOG_DIR}/${script_basename}-"*.log 2>/dev/null | head -1)
        if [[ -n "$logfile" && -f "$logfile" ]]; then
            last_line=$(tail -1 "$logfile" 2>/dev/null \
                | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
                | tr -d '\r' \
                | cut -c1-72)
        fi

        clear
        show_header
        echo -e "  ${PRIMARY}▶${NC} ${BOLD}Running:${NC} ${title}"
        printf "  ${INFO}Elapsed:${NC} %dm %02ds\n" "$mins" "$secs"
        if [[ -n "$last_line" ]]; then
            echo -e "  ${INFO}Latest:${NC}  ${last_line}"
        fi
        echo ""
        echo -e "  ${INFO}Output is streaming in the right pane.${NC}"
        echo -e "  ${INFO}Press Enter there to return to the menu.${NC}"
        echo ""
        echo -e "${PRIMARY}──────────────────────────────────────────────────────────${NC}"
        echo -e "${INFO}Alt+←/→ switch panes  •  Ctrl+b [ scrollback${NC}"
    done
}

# Execute a script in the persistent output pane (tmux) or inline (fallback).
# Inside tmux the menu stays in the left pane and the script output streams in
# the always-on right pane, driven by lib/output_pane.sh.  tmux wait-for keeps
# the menu blocked until the user dismisses the run.
#
# @param script_name The filename of the script to execute (relative to SCRIPT_DIR)
# @param window_title Human-readable title shown in the output pane header
# @return 0 if successful, 1 if script not found
# Usage: run_script "scripts/script_name.sh" "Display Title"
run_script() {
    local script_name="$1"
    local window_title="$2"
    local full_path="${SCRIPT_DIR}${script_name}"

    if [[ ! -f "$full_path" ]]; then
        echo -e "\n${DANGER}✘ Error:${NC} ${script_name} not found in ${SCRIPT_DIR}"
        echo -e "${INFO}Press Enter to return to menu...${NC}"
        read -r
        return 1
    fi

    chmod +x "$full_path"

    # Tell every child script that confirm_reboot should *defer* rather than
    # prompt — run.sh collects the flag and prompts once at the end.
    export FPI_DEFER_REBOOT=1

    if [[ -n "$TMUX" && -n "$FPI_OUTPUT_PANE" ]]; then
        local signal="fpi_run_$$_${RANDOM}"
        # Move focus to the output pane FIRST so any prompt the script emits
        # (sudo password, y/N confirmations) reads keystrokes from the right
        # pane where the prompt is actually visible.
        tmux select-pane -t "$FPI_OUTPUT_PANE"
        tmux respawn-pane -k -t "$FPI_OUTPUT_PANE" \
            "bash '${SCRIPT_DIR}lib/output_pane.sh' run '${full_path}' '${window_title}' '${signal}'"
        # Fork a live status updater for the menu pane and tear it down once
        # the script signals it's done. The wait-for here previously timed out
        # at 1h; long firmware+driver flows can exceed that, so drop the
        # timeout entirely and trust the output pane to signal.
        show_running_state_live "$window_title" "$(basename "$full_path" .sh)" &
        local watcher_pid=$!
        tmux wait-for "$signal" 2>/dev/null || true
        kill "$watcher_pid" 2>/dev/null || true
        wait "$watcher_pid" 2>/dev/null || true
        tmux select-pane -t "${FPI_MENU_PANE:-:.0}"
    else
        # Fallback when tmux is unavailable: run inline (original behaviour).
        clear
        echo -e "${BANNER}╭──────────────────────────────────────────────────────────╮${NC}"
        echo -e "${BANNER}│${NC}  ${BOLD}${window_title}${NC}"
        echo -e "${BANNER}╰──────────────────────────────────────────────────────────╯${NC}"
        echo ""
        bash "$full_path"
        local exit_code=$?
        echo ""
        echo -e "${PRIMARY}──────────────────────────────────────────────────────────${NC}"
        if [[ $exit_code -eq 0 ]]; then
            echo -e "${SUCCESS}✓ Completed successfully!${NC}"
        else
            echo -e "${WARNING}⚠ Completed with exit code: $exit_code${NC}"
        fi
        echo -e "${INFO}Press Enter to return to menu...${NC}"
        read -r
    fi
}

# Display the main menu interface with arrow key navigation
# Shows all available configuration options with descriptions
# Highlights the currently selected option
# Usage: show_menu selected_index
show_menu() {
    local selected_index="$1"
    show_header

    # Pad the visible label to a fixed column so the reverse-video highlight
    # bar fills the row consistently instead of trailing off after each label.
    local label_width=54

    for i in "${!MENU_ITEMS[@]}"; do
        local item="${MENU_ITEMS[$i]}"
        # Three-field format: key|Display|Description
        local key="${item%%|*}"
        local rest="${item#*|}"
        local text="${rest%%|*}"
        local desc="${rest#*|}"
        [[ "$desc" == "$rest" ]] && desc=""  # no third field

        # A single visible glyph for the done marker — keeps the printf width
        # calculation honest (escape sequences inside the format string would
        # throw off %-Ns padding).
        local glyph=" "
        if [[ ! "$key" =~ ^_ ]] && is_done "$key"; then
            glyph="✓"
        fi

        # Numbering shown to the user is 1-based; index 0 reads as "press 1".
        local human_idx=$((i + 1))

        if [[ $i -eq $selected_index ]]; then
            printf "${HIGHLIGHT}${PRIMARY}  ►${NC}${HIGHLIGHT} ${BOLD}%s %-${label_width}s${NC}\n" \
                "$glyph" "$text"
            if [[ -n "$desc" ]]; then
                printf "${HIGHLIGHT}     %-${label_width}s${NC}\n" "$desc"
            fi
        else
            local glyph_colored="$glyph"
            [[ "$glyph" == "✓" ]] && glyph_colored="${SUCCESS}✓${NC}"
            echo -e "${PRIMARY}  ${human_idx})${NC} ${glyph_colored} ${BOLD}${text}${NC}"
            if [[ -n "$desc" ]]; then
                echo -e "     ${INFO}${desc}${NC}"
            fi
        fi
        echo ""
    done

    echo -e "${PRIMARY}──────────────────────────────────────────────────────────${NC}"
    echo -e "${INFO}↑↓/jk navigate  •  1-9 jump  •  Enter select  •  q quit${NC}"
    echo -e "${INFO}Alt+←/→ switch panes  •  Ctrl+b [ scrollback${NC}"
    if [[ -f "$FPI_DONE_FILE" ]]; then
        echo -e "${INFO}State: ${FPI_DONE_FILE}${NC}"
    fi
}

# Map a key (script basename without .sh) to its display title from MENU_ITEMS,
# falling back to the key itself when not found. Used by run_by_key.
title_for_key() {
    local needle="$1" item key text rest
    for item in "${MENU_ITEMS[@]}"; do
        key="${item%%|*}"
        if [[ "$key" == "$needle" ]]; then
            rest="${item#*|}"
            text="${rest%%|*}"
            echo "$text"
            return 0
        fi
    done
    echo "$needle"
}

# Run a single script by key. Used by both the menu and --run.
run_by_key() {
    local key="$1"
    local title
    title=$(title_for_key "$key")
    run_script "scripts/${key}.sh" "$title"
}

# Chain the baseline. Stops at the first failure to avoid compounding errors
# in a single sudo session.
run_baseline() {
    local key
    echo -e "${INFO}Running recommended baseline: ${BASELINE_KEYS[*]}${NC}"
    for key in "${BASELINE_KEYS[@]}"; do
        if ! run_by_key "$key"; then
            echo -e "${DANGER}✘ Baseline stopped at: $key${NC}"
            return 1
        fi
    done
}

# Preflight that the menu loop calls once before accepting any selection.
# Two jobs:
#   1. Confirm we can reach Fedora's mirror infrastructure (a DNS miss here
#      would otherwise surface 25 minutes into a dnf transaction).
#   2. Prime sudo credentials and keep them warm with a background loop so
#      a long install doesn't trip the sudo timestamp timeout mid-run.
# The keepalive child is teared down via an EXIT trap below.
run_preflight() {
    echo -e "${INFO}Running preflight checks...${NC}"

    if ! getent hosts mirrors.fedoraproject.org &>/dev/null; then
        echo -e "${DANGER}✘ Cannot resolve mirrors.fedoraproject.org${NC}"
        echo -e "${INFO}Check DNS / internet connectivity and try again.${NC}"
        return 1
    fi
    echo -e "${SUCCESS}✓${NC} Network reachable"

    # Skip sudo entirely in dry-run mode — every privileged call will be
    # intercepted by runtime.sh's sudo override and printed, never executed.
    if [[ "${FPI_DRY_RUN:-0}" = "1" ]]; then
        echo -e "${SUCCESS}✓${NC} dry-run mode — skipping sudo prime"
        return 0
    fi

    echo -e "${INFO}Priming sudo credentials (you may be prompted)...${NC}"
    # `command sudo` bypasses the dry-run override (we just guarded above,
    # but staying explicit so this can't regress under refactors).
    if ! command sudo -v; then
        echo -e "${DANGER}✘ sudo authentication failed${NC}"
        return 1
    fi
    echo -e "${SUCCESS}✓${NC} sudo primed"

    # Background keepalive: refresh sudo timestamp every 60s until run.sh
    # exits. Captures the parent PID explicitly so the child dies cleanly
    # even if exec replaces the parent (e.g. the Exit menu path).
    local parent_pid=$$
    (
        while sleep 60; do
            command sudo -nv 2>/dev/null || exit 0
            kill -0 "$parent_pid" 2>/dev/null || exit 0
        done
    ) &
    FPI_SUDO_KEEPALIVE_PID=$!
    trap 'kill "${FPI_SUDO_KEEPALIVE_PID:-0}" 2>/dev/null || true' EXIT

    return 0
}

# Read a single user keystroke and emit a normalized token.
#
# Supported:
#   ↑/↓ arrows or k/j (vim style)           -> UP / DOWN
#   Home/End                                -> HOME / END
#   Enter                                   -> ENTER
#   Esc (alone) or q/Q                      -> QUIT
#   1-9                                     -> the digit itself (for direct
#                                              menu selection in main_loop)
#   Anything else                           -> the raw character
read_key() {
    local key
    read -r -s -n1 key 2>/dev/null >&2

    if [[ $key == $'\x1b' ]]; then
        # Read the rest of the escape sequence with a short timeout. A bare
        # Esc (timeout fires with empty buffer) is treated as QUIT.
        local seq
        read -r -s -n2 -t 0.1 seq 2>/dev/null >&2
        case $seq in
            '[A') echo "UP" ;;
            '[B') echo "DOWN" ;;
            '[H'|'[1') echo "HOME" ;;
            '[F'|'[4') echo "END" ;;
            '')   echo "QUIT" ;;
            *)    echo "OTHER" ;;
        esac
    elif [[ -z $key ]]; then
        echo "ENTER"
    elif [[ $key == "q" || $key == "Q" ]]; then
        echo "QUIT"
    elif [[ $key == "k" ]]; then
        echo "UP"
    elif [[ $key == "j" ]]; then
        echo "DOWN"
    else
        echo "$key"
    fi
}

# Main program loop that handles arrow key navigation and script execution
# Continuously displays the menu and processes user input until exit is selected
#
# This function implements the core user interface logic:
# - Displays the main menu with highlighted selection
# - Captures arrow key input for navigation
# - Routes to appropriate script execution based on selection
# - Handles invalid input with error messages
# - Provides feedback for each action
main_loop() {
    local selected=0
    local total_options=${#MENU_ITEMS[@]}

    # Preflight runs once before the menu is shown — a failure here is fatal
    # because everything downstream needs network + sudo.
    if ! run_preflight; then
        echo -e "${DANGER}✘ Preflight failed — exiting.${NC}"
        sleep 3
        if [[ -n "$TMUX" ]]; then
            exec tmux kill-server
        fi
        exit 1
    fi

    while true; do
        show_menu $selected
        local k
        k=$(read_key)

        case $k in
            "UP")   [[ $selected -gt 0 ]] && ((selected--)) ;;
            "DOWN") [[ $selected -lt $((total_options - 1)) ]] && ((selected++)) ;;
            "HOME") selected=0 ;;
            "END")  selected=$((total_options - 1)) ;;
            "QUIT") dispatch_selection "$((total_options - 1))" ;;
            "ENTER") dispatch_selection "$selected" ;;
            [1-9])
                # 1-based direct selection — jump to the entry and dispatch.
                local idx=$((k - 1))
                if [[ $idx -lt $total_options ]]; then
                    selected=$idx
                    dispatch_selection "$idx"
                fi
                ;;
        esac
    done
}

# Run the entry at the given menu index. Shared between ENTER, QUIT (which
# resolves to the Exit entry), and 1-9 direct selection.
dispatch_selection() {
    local idx="$1"
    local item="${MENU_ITEMS[$idx]}"
    local key="${item%%|*}"
    case "$key" in
        _exit)
            prompt_deferred_reboot
            echo -e "\n${DANGER}Exiting. Enjoy your new Fedora setup!${NC}"
            if [[ -n "$TMUX" ]]; then
                exec tmux kill-server
            fi
            exit 0
            ;;
        _baseline) run_baseline ;;
        *)         run_by_key "$key" ;;
    esac
}

# If any script in the session flagged a reboot, ask once before exiting.
# Honours the same `confirm_reboot` y/N semantics as the per-script prompt
# used to, but consolidated.
prompt_deferred_reboot() {
    if ! reboot_needed; then
        return 0
    fi
    echo
    echo -e "${WARNING}One or more scripts in this session flagged a reboot:${NC}"
    while IFS= read -r line; do
        echo -e "  • ${line}"
    done < "$FPI_REBOOT_MARKER"
    echo
    read -r -p "  Reboot now? [y/N] " ans
    clear_reboot_marker
    case "$ans" in
        [yY]|[yY][eE][sS])
            echo -e "${INFO}Rebooting...${NC}"
            sudo reboot
            ;;
        *)
            echo -e "${INFO}Reboot skipped — run 'sudo reboot' when ready.${NC}"
            ;;
    esac
}

# --- Non-interactive entry point (--run KEY / --run all) ---
# Runs without tmux, without the menu. Output streams to the terminal AND to
# the standard log directory (lib/output_pane.sh's logfile pattern is not
# used here because there's no pane; we just tee directly).
run_noninteractive() {
    local target="$1"

    # Still preflight — non-interactive callers benefit from the network +
    # sudo check too.
    if ! run_preflight; then
        echo -e "${DANGER}✘ Preflight failed — exiting.${NC}"
        exit 1
    fi

    export FPI_DEFER_REBOOT=1
    fpi_ensure_state_dirs

    local rc=0
    if [[ "$target" == "all" ]]; then
        local key
        for key in "${BASELINE_KEYS[@]}"; do
            _noninteractive_one "$key" || { rc=1; break; }
        done
    else
        _noninteractive_one "$target" || rc=1
    fi

    prompt_deferred_reboot
    exit "$rc"
}

_noninteractive_one() {
    local key="$1"
    local script_path="${SCRIPT_DIR}scripts/${key}.sh"
    if [[ ! -f "$script_path" ]]; then
        echo "Error: no such script: $script_path" >&2
        echo "Run './run.sh --list' to see available keys." >&2
        return 2
    fi

    local logfile
    logfile="${FPI_LOG_DIR}/${key}-$(date +%Y%m%d-%H%M%S).log"
    echo -e "${INFO}▶ Running ${key} (log: ${logfile})${NC}"

    local rc=0
    bash "$script_path" 2>&1 | tee "$logfile" || true
    rc=${PIPESTATUS[0]}

    if [[ $rc -eq 0 ]]; then
        mark_done "$key"
        echo -e "${SUCCESS}✓ ${key} completed${NC}"
    else
        echo -e "${WARNING}⚠ ${key} exited with $rc${NC}"
    fi
    return "$rc"
}

# --- Entry dispatch ---
if [[ -n "$FPI_NONINTERACTIVE" ]]; then
    run_noninteractive "$FPI_RUN_TARGET"
else
    main_loop
fi