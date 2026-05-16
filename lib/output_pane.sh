#!/bin/bash

# =============================================================================
# OUTPUT PANE HELPER
# =============================================================================
# Drives the persistent right-side tmux output pane used by run.sh.
#
# Subcommands:
#   idle                          Show the idle screen and sleep until killed.
#   run <script> <title> <signal> Run <script>, frame it with header/footer,
#                                 then signal the menu pane and return to idle.
# =============================================================================

set -Eeuo pipefail

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_LIB_DIR}/ui.sh"
source "${SCRIPT_LIB_DIR}/logging.sh"
source "${SCRIPT_LIB_DIR}/runtime.sh"

show_idle() {
    clear
    echo
    echo -e "  ${BANNER}╭──────────────────────────────────────────────────────╮${NC}"
    echo -e "  ${BANNER}│${NC}                                                      ${BANNER}│${NC}"
    echo -e "  ${BANNER}│${NC}    ${BOLD}Fedora Post-Install — Output${NC}                      ${BANNER}│${NC}"
    echo -e "  ${BANNER}│${NC}                                                      ${BANNER}│${NC}"
    echo -e "  ${BANNER}│${NC}    ${INFO}Pick an option from the menu on the left.${NC}        ${BANNER}│${NC}"
    echo -e "  ${BANNER}│${NC}    ${INFO}Its output will stream here.${NC}                      ${BANNER}│${NC}"
    echo -e "  ${BANNER}│${NC}                                                      ${BANNER}│${NC}"
    echo -e "  ${BANNER}╰──────────────────────────────────────────────────────╯${NC}"
    echo
    trap 'exit 0' TERM INT
    while :; do sleep 3600; done
}

run_target() {
    local target="$1" title="$2" signal="$3"

    # Tee everything to a timestamped log file so output isn't lost when the
    # pane is dismissed. Logs live under $FPI_LOG_DIR (XDG_STATE_HOME/fpi/logs).
    fpi_ensure_state_dirs
    local logfile
    logfile="${FPI_LOG_DIR}/$(basename "$target" .sh)-$(date +%Y%m%d-%H%M%S).log"

    clear
    echo -e "${BANNER}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${BANNER}│${NC}  ${BOLD}${title}${NC}"
    echo -e "${BANNER}╰──────────────────────────────────────────────────────────╯${NC}"
    echo -e "${INFO}Log file: ${logfile}${NC}"
    echo

    # Phase 1 — script is running.
    # Ctrl+C sends SIGINT to the whole process group. The child script exits;
    # bash then fires our deferred INT trap. We show a notice and unblock the
    # menu immediately — the user does not need to press Enter.
    trap 'echo
echo -e "${PRIMARY}──────────────────────────────────────────────────────────${NC}"
echo -e "${YELLOW}⚠ Cancelled${NC}"
tmux wait-for -S "$signal" 2>/dev/null
trap - INT TERM
show_idle' INT TERM

    # `set -e` is on for output_pane.sh itself, but the pipeline can fail
    # without us wanting to abort here — we need to inspect $rc. Disable -e
    # only for the duration of the run, then re-enable.
    local rc
    set +e
    bash "$target" 2>&1 | tee "$logfile"
    rc=${PIPESTATUS[0]}
    set -e

    # Mark the script as done in the menu state file when it succeeded.
    # Runtime helpers come from runtime.sh; guard in case they ever fail to load.
    if [[ $rc -eq 0 ]] && declare -F mark_done &>/dev/null; then
        mark_done "$(basename "$target" .sh)"
    fi

    # Phase 2 — script exited on its own. Keep a lighter trap active so that
    # Ctrl+C at the "Press Enter" prompt also returns to the menu cleanly.
    trap 'tmux wait-for -S "$signal" 2>/dev/null; trap - INT TERM; show_idle' INT TERM

    echo
    echo -e "${PRIMARY}──────────────────────────────────────────────────────────${NC}"
    if [[ $rc -eq 0 ]]; then
        echo -e "${SUCCESS}✓ Completed successfully!${NC}"
    elif [[ $rc -eq 130 ]]; then
        echo -e "${YELLOW}⚠ Cancelled${NC}"
    else
        echo -e "${YELLOW}⚠ Completed with exit code: ${rc}${NC}"
    fi
    echo -e "${INFO}Log saved to: ${logfile}${NC}"
    echo -e "${INFO}Press Enter or Ctrl+C to return to the menu...${NC}"
    read -r _ 2>/dev/null || true

    # Unblock the menu pane, then idle so this pane stays alive for the next run.
    trap - INT TERM
    tmux wait-for -S "$signal" 2>/dev/null
    show_idle
}

case "${1:-idle}" in
    idle) show_idle ;;
    run)  run_target "$2" "$3" "$4" ;;
    *)    echo "Unknown subcommand: $1" >&2; exit 1 ;;
esac
