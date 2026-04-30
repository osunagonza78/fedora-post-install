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

set -u

BANNER='\033[1;35m'
PRIMARY='\033[1;34m'
SUCCESS='\033[1;32m'
WARNING='\033[1;33m'
INFO='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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

    clear
    echo -e "${BANNER}##########################################################${NC}"
    echo -e "${BANNER}#${NC}  ${BOLD}${title}${NC}"
    echo -e "${BANNER}##########################################################${NC}"
    echo

    bash "$target"
    local rc=$?

    echo
    echo -e "${PRIMARY}──────────────────────────────────────────────────────────${NC}"
    if [[ $rc -eq 0 ]]; then
        echo -e "${SUCCESS}✓ Completed successfully!${NC}"
    else
        echo -e "${WARNING}⚠ Completed with exit code: ${rc}${NC}"
    fi
    echo -e "${INFO}Press Enter to return to the menu...${NC}"
    read -r _

    # Unblock the menu pane, then idle so this pane stays alive for the next run.
    tmux wait-for -S "$signal" 2>/dev/null
    show_idle
}

case "${1:-idle}" in
    idle) show_idle ;;
    run)  run_target "$2" "$3" "$4" ;;
    *)    echo "Unknown subcommand: $1" >&2; exit 1 ;;
esac
