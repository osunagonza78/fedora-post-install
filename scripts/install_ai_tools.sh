#!/bin/bash

# =============================================================================
# AI Tools Installation Script for Fedora
# =============================================================================
# This script handles the installation of AI tools (Ollama, OpenCode, Claude).
# It allows the user to select specific tools or install all of them.
#
# Author: Gilberto Osuna Gonzalez
# Version: 1.0
# =============================================================================

set -Eeuo pipefail

# Source logging and runtime libraries
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib/logging.sh"
source "${SCRIPT_DIR}/../lib/verify.sh"
source "${SCRIPT_DIR}/../lib/runtime.sh"
require_fedora

# -----------------------------------------------------------------------------
# TOOL DEFINITIONS
# -----------------------------------------------------------------------------
# Format: "Display Name|Install Command|Check Command"
AI_TOOLS=(
    "Ollama|curl -fsSL https://ollama.com/install.sh | sh|ollama"
    "OpenCode|curl -fsSL https://opencode.ai/v2/install | bash|opencode"
    "Claude|curl -fsSL https://claude.ai/install.sh | bash|claude"
)

# -----------------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------------

# Checks if a tool is already installed
# @param check_cmd The command to run to verify installation
# @return 0 if installed, 1 otherwise
is_installed() {
    local check_cmd="$1"
    if command -v "$check_cmd" &>/dev/null; then
        return 0
    fi
    return 1
}

# Installs a specific AI tool
# @param name The display name of the tool
# @param install_cmd The command used to install the tool
# @param check_cmd The command used to verify the installation
install_tool() {
    local name="$1"
    local install_cmd="$2"
    local check_cmd="$3"

    if is_installed "$check_cmd"; then
        log_info "$name is already installed. Skipping..."
        return 0
    fi

    log_info "Installing $name..."
    
    # Use sudo for installation as these usually require root permissions
    if ! eval "sudo $install_cmd"; then
        log_error "Failed to install $name"
        return 1
    fi

    if is_installed "$check_cmd"; then
        log_success "$name installed successfully"
    else
        log_error "Installation of $name failed (command $check_cmd not found after install)"
        return 1
    fi
}

# Interactive selection menu for AI tools
# @return 0 if operations complete successfully, 1 if any selected tool fails
select_and_install_tools() {
    echo
    print_section_header "AI TOOLS INSTALLATION"
    echo "Select which AI tools you would like to install:"
    echo "----------------------------------------------------------"
    
    local i=1
    for tool in "${AI_TOOLS[@]}"; do
        local name="${tool%%|*}"
        echo "  $i) $name"
        ((i++))
    done
    echo "  a) All"
    echo "  n) None / Cancel"
    echo "----------------------------------------------------------"
    
    read -r -p "Selection: " choice

    local tools_to_install=()

    case "$choice" in
        [aA])
            # Add all tools to the list
            for tool in "${AI_TOOLS[@]}"; do
                tools_to_install+=("$tool")
            done
            ;;
        [nN])
            log_info "AI tools installation cancelled by user."
            return 0
            ;;
        [0-9]*)
            # Validate and add specific tool
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                local idx=$((choice - 1))
                if [[ $idx -ge 0 && $idx -lt ${#AI_TOOLS[@]} ]]; then
                    tools_to_install+=("${AI_TOOLS[$idx]}")
                else
                    log_error "Invalid selection: $choice"
                    return 1
                fi
            else
                log_error "Invalid selection: $choice"
                return 1
            fi
            ;;
        *)
            log_error "Invalid selection: $choice"
            return 1
            ;;
    esac

    # Perform installation of selected tools
    local failures=0
    for tool_entry in "${tools_to_install[@]}"; do
        # Split the tool entry: Name|InstallCmd|CheckCmd
        local name="${tool_entry%%|*}"
        local remaining="${tool_entry#*|}"
        local install_cmd="${remaining%%|*}"
        local check_cmd="${remaining#*|}"

        if ! install_tool "$name" "$install_cmd" "$check_cmd"; then
            ((failures++))
        fi
    done

    if [[ $failures -gt 0 ]]; then
        log_error "$failures AI tool(s) failed to install."
        return 1
    fi

    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting AI Tools installation process..."
    
    if ! select_and_install_tools; then
        exit 1
    fi
    
    log_success "AI Tools configuration completed successfully!"
}

main "$@"
