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

# --- Color Palette ---
BANNER='\033[1;35m'  # Bold Magenta
PRIMARY='\033[1;34m' # Bold Blue
SUCCESS='\033[1;32m' # Bold Green
WARNING='\033[1;33m' # Bold Yellow
DANGER='\033[1;31m'  # Bold Red
INFO='\033[0;36m'    # Cyan
NC='\033[0m'         # No Color
BOLD='\033[1m'
HIGHLIGHT='\033[7m'   # Reverse video for selected item

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/"

# --- Auto-launch in tmux for split-pane view ---
# If tmux is available and we're not already inside a session, re-exec inside one.
# This enables the script output to appear in a split pane below the menu.
if command -v tmux &>/dev/null && [[ -z "$TMUX" ]]; then
    exec tmux new-session "bash \"${SCRIPT_DIR}run.sh\""
fi

# =============================================================================
# FUNCTIONS
# =============================================================================

# Display the application header and title
# Creates a clean, branded interface showing the tool name and purpose
# Usage: show_header
show_header() {
    clear
    echo -e "${BANNER}##########################################################${NC}"
    echo -e "${BANNER}#${NC}             ${BOLD}FEDORA POST-INSTALL TOOL${NC}               ${BANNER}#${NC}"
    echo -e "${BANNER}##########################################################${NC}"
    echo ""
}

# Execute a script in a split pane (tmux) or inline fallback.
# When running inside tmux the menu stays visible in the top pane while the
# script's output streams in a new bottom pane.  When the script finishes the
# user presses Enter to dismiss the bottom pane and the menu is immediately
# ready for the next selection.
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
        read
        return 1
    fi

    chmod +x "$full_path"

    if [[ -n "$TMUX" ]]; then
        # Split the current window: bottom pane (65 % of height) runs the script.
        # The top pane keeps the menu and redraws itself while the script runs.
        # $full_path and $window_title are expanded by the outer shell here;
        # \$_rc is intentionally escaped so it is evaluated inside the pane.
        tmux split-window -v -p 65 "
            echo -e '\033[1;35m##########################################################\033[0m'
            echo -e '\033[1;35m#\033[0m  \033[1m $window_title\033[0m'
            echo -e '\033[1;35m##########################################################\033[0m'
            echo ''
            bash '$full_path'
            _rc=\$?
            echo ''
            echo -e '\033[1;34m──────────────────────────────────────────────────────────\033[0m'
            if [[ \$_rc -eq 0 ]]; then
                echo -e '\033[1;32m✓ Completed successfully!\033[0m'
            else
                echo -e '\033[1;33m⚠ Completed with exit code: \$_rc\033[0m'
            fi
            echo -e '\033[0;36mPress Enter to close this panel...\033[0m'
            read
        "
    else
        # Fallback when tmux is unavailable: run inline (original behaviour).
        clear
        echo -e "${BANNER}##########################################################${NC}"
        echo -e "${BANNER}#${NC}  ${BOLD}${window_title}${NC}"
        echo -e "${BANNER}##########################################################${NC}"
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
        read
    fi
}

# Display the main menu interface with arrow key navigation
# Shows all available configuration options with descriptions
# Highlights the currently selected option
# Usage: show_menu selected_index
show_menu() {
    local selected_index="$1"
    show_header
    
    # Menu items array: [display_text, description]
    local -a menu_items=(
        "System Configuration|Optimize DNF, set hostname, and tune system limits."
        "Packages Installation|Enable RPM Fusion, Flatpak, and install essential apps."
        "Development Environment Installation|Install Development Tools."
        "Virtualization Stack|Install KVM/QEMU hypervisor and libvirt services."
        "Secure Boot Config|Generate and enroll MOK keys for 3rd party modules."
        "Nvidia Drivers|Install latest proprietary drivers via Akmod."
        "Exit|"
    )
    
    for i in "${!menu_items[@]}"; do
        local item="${menu_items[$i]}"
        local text="${item%%|*}"
        local desc="${item#*|}"
        
        if [[ $i -eq $selected_index ]]; then
            echo -e "${HIGHLIGHT}${PRIMARY}  ►${NC}${HIGHLIGHT} ${BOLD}${text}${NC}"
            if [[ -n "$desc" ]]; then
                echo -e "${HIGHLIGHT}     ${INFO}${desc}${NC}"
            fi
        else
            echo -e "${PRIMARY}  ${i})${NC} ${BOLD}${text}${NC}"
            if [[ -n "$desc" ]]; then
                echo -e "     ${INFO}${desc}${NC}"
            fi
        fi
        echo ""
    done
    
    echo -e "${PRIMARY}──────────────────────────────────────────────────────────${NC}"
    echo -e "${INFO}Use ↑↓ arrows to navigate, Enter to select${NC}"
}

# Read single character input for arrow key navigation
# Captures arrow keys, Enter, and other special keys
# Usage: read_key
read_key() {
    local key
    read -s -n1 key 2>/dev/null >&2
    
    if [[ $key == $'\x1b' ]]; then
        read -s -n2 -t 0.1 key 2>/dev/null >&2
        case $key in
            '[A') echo "UP" ;;
            '[B') echo "DOWN" ;;
            *) echo "OTHER" ;;
        esac
    elif [[ $key == "" ]]; then
        echo "ENTER"
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
    local total_options=7
    
    while true; do
        show_menu $selected
        local key=$(read_key)
        
        case $key in
            "UP")
                ((selected--))
                if [[ $selected -lt 0 ]]; then
                    selected=$((total_options - 1))
                fi
                ;;
            "DOWN")
                ((selected++))
                if [[ $selected -ge $total_options ]]; then
                    selected=0
                fi
                ;;
            "ENTER")
                case $selected in
                    0) run_script scripts/system_configuration.sh    "System Configuration" ;;
                    1) run_script scripts/packages_installation.sh   "Packages Installation" ;;
                    2) run_script scripts/development_installation.sh "Development Tools Installation" ;;
                    3) run_script scripts/virtualization_installation.sh "Virtualization Stack Installation" ;;
                    4) run_script scripts/configure_secureboot.sh    "Secure Boot Configuration" ;;
                    5) run_script scripts/nvidia_drivers.sh          "Nvidia Driver Installation" ;;
                    6)
                        echo -e "\n${DANGER}Exiting. Enjoy your new Fedora setup!${NC}"
                        exit 0
                        ;;
                esac
                ;;
        esac
    done
}

# Execute the main program loop
main_loop