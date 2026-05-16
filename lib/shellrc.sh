#!/bin/bash

# =============================================================================
# SHELLRC LIBRARY
# =============================================================================
# Idempotent shell rc-file writes. Used by configure_shell_environment in both
# packages_installation.sh and development_installation.sh (and any future
# script that wants to drop init snippets into the user's shell config).
#
# Knows about bash, zsh, and fish. Detects via $SHELL, falls back to bash.
# Each append is gated by a marker comment so re-runs are no-ops.
# =============================================================================

# Path of the user's login-shell rc file.
detect_shell_rc() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    case "$shell_name" in
        bash)  echo "$HOME/.bashrc" ;;
        zsh)   echo "$HOME/.zshrc" ;;
        fish)  echo "$HOME/.config/fish/config.fish" ;;
        *)     echo "$HOME/.bashrc" ;;
    esac
}

detect_shell_name() {
    basename "${SHELL:-/bin/bash}"
}

# Append a block to the user's shellrc if `marker` is not already present.
# `bash_block` covers bash and zsh (identical syntax). `fish_block` is
# optional — when the user's shell is fish and no fish_block is supplied,
# the call is skipped with a warning.
#
# Always timestamps a backup of the rc file before writing.
#
# Usage:
#   append_if_missing "# fpi: Java and Gradle" "export JAVA_HOME=..."
#   append_if_missing "# fpi: Java and Gradle" "$bash_block" "$fish_block"
append_if_missing() {
    local marker="$1"
    local bash_block="$2"
    local fish_block="${3:-}"

    local shell_name rc_file block
    shell_name=$(detect_shell_name)

    case "$shell_name" in
        bash)
            rc_file="$HOME/.bashrc"
            block="$bash_block"
            ;;
        zsh)
            rc_file="$HOME/.zshrc"
            block="$bash_block"
            ;;
        fish)
            if [[ -z "$fish_block" ]]; then
                log_warning "Detected fish shell — no fish-syntax block supplied for '${marker}'"
                log_warning "Add the equivalent to ~/.config/fish/config.fish manually."
                return 0
            fi
            rc_file="$HOME/.config/fish/config.fish"
            block="$fish_block"
            ;;
        *)
            rc_file="$HOME/.bashrc"
            block="$bash_block"
            log_warning "Unrecognised shell '${shell_name}' — writing to ~/.bashrc as fallback"
            ;;
    esac

    if [[ -f "$rc_file" ]] && grep -qF "$marker" "$rc_file" 2>/dev/null; then
        log_info "$(basename "$rc_file") already contains '${marker}' — skipping"
        return 0
    fi

    mkdir -p "$(dirname "$rc_file")"
    if [[ -f "$rc_file" ]]; then
        cp "$rc_file" "${rc_file}.backup.$(date +%Y%m%d_%H%M%S)" \
            || log_warning "Failed to backup $rc_file"
    fi

    {
        echo
        echo "$marker"
        echo "$block"
    } >> "$rc_file"
    log_success "Appended shell config to $rc_file"
}
