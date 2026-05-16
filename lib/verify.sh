#!/bin/bash

# =============================================================================
# VERIFY LIBRARY
# =============================================================================
# Shared safety utilities: reboot confirmation, CPU capability checks,
# and downloaded-file checksum verification.
#
# Usage: source "$(dirname "$0")/../lib/verify.sh"
# Requires: lib/logging.sh must be sourced first
# =============================================================================

# Abort unless we're running on Fedora 41 or newer. Combines two guards:
#   1. `/etc/fedora-release` must exist (no silent fallthrough on Ubuntu/Arch).
#   2. Fedora major version >= 41, which is the floor where DNF5 is the
#      default — the rest of the codebase assumes DNF5 syntax.
# This is a hard precondition; callers should invoke it before sourcing
# lib/versions.sh (which derives URLs from FEDORA_VERSION).
require_fedora() {
    if [[ ! -f /etc/fedora-release ]]; then
        log_error "This tool only supports Fedora Linux."
        log_error "/etc/fedora-release not found — aborting."
        exit 1
    fi

    if ! command -v rpm &>/dev/null; then
        log_error "rpm not found — cannot determine Fedora version."
        exit 1
    fi

    local ver
    ver=$(rpm -E %fedora 2>/dev/null)

    if [[ -z "$ver" || ! "$ver" =~ ^[0-9]+$ ]]; then
        log_error "Could not parse Fedora version from rpm -E %fedora."
        exit 1
    fi

    if (( ver < 41 )); then
        log_error "This tool requires Fedora 41 or newer (DNF5 syntax)."
        log_error "Detected Fedora version: $ver"
        log_error "On older Fedora, the dnf invocations in this tool will misbehave."
        exit 1
    fi
}

# Prompt the user before rebooting — or, when invoked from run.sh's menu,
# defer the prompt to the end of the session via mark_reboot_needed.
#
# Deferral is triggered by FPI_DEFER_REBOOT being set in the environment
# (run.sh exports it before launching any script). This collapses the 3
# separate reboot prompts a full menu run used to produce into one prompt
# at the end of the session.
#
# Standalone script invocations (./scripts/foo.sh outside the menu) keep
# the interactive prompt.
#
# Usage: confirm_reboot "Reason message"
confirm_reboot() {
    local reason="${1:-This change requires a reboot to take effect.}"
    echo

    if [[ -n "${FPI_DEFER_REBOOT:-}" ]]; then
        if declare -F mark_reboot_needed &>/dev/null; then
            mark_reboot_needed "$reason"
        fi
        log_warning "$reason"
        log_info "Reboot deferred — run.sh will prompt once at end of session."
        return 0
    fi

    log_warning "$reason"
    read -r -p "  Reboot now? [y/N] " _reboot_response
    echo
    case "$_reboot_response" in
        [yY][eE][sS]|[yY])
            log_info "Rebooting..."
            sudo reboot
            ;;
        *)
            log_info "Reboot skipped. Please reboot manually when ready."
            ;;
    esac
}

# Verify that the running CPU supports hardware virtualisation.
# Checks /proc/cpuinfo for VMX (Intel) or SVM (AMD) flags.
#
# Usage: check_cpu_virtualization || return 1
check_cpu_virtualization() {
    log_info "Checking CPU virtualisation support..."
    if ! grep -qE '(vmx|svm)' /proc/cpuinfo; then
        log_error "CPU does not support hardware virtualisation (no VMX/SVM flags found in /proc/cpuinfo)"
        log_error "KVM requires a CPU with virtualisation extensions enabled in BIOS/UEFI"
        return 1
    fi
    log_success "CPU virtualisation supported ($(grep -oE '(vmx|svm)' /proc/cpuinfo | head -1 | tr '[:lower:]' '[:upper:]'))"
    return 0
}

# Verify a downloaded file against an expected SHA-256 checksum.
# Prints a clear error if the checksum does not match and removes the bad file.
#
# Usage: verify_checksum "/path/to/file" "expected_hex_string"
verify_checksum() {
    local file="$1"
    local expected="$2"

    if [ ! -f "$file" ]; then
        log_error "Cannot verify checksum: file not found: $file"
        return 1
    fi

    log_info "Verifying checksum for $(basename "$file")..."
    local actual
    actual=$(sha256sum "$file" | awk '{print $1}')

    if [ "$actual" != "$expected" ]; then
        log_error "Checksum MISMATCH for $(basename "$file")"
        log_error "  Expected: $expected"
        log_error "  Got:      $actual"
        rm -f "$file"
        return 1
    fi

    log_success "Checksum OK: $(basename "$file")"
    return 0
}

# Fetch a SHA-256 checksum from a URL and verify a downloaded file against it.
# Handles two checksum-file formats:
#   1. Single-file sibling (e.g. `foo.tar.gz.sha256`): first whitespace token
#      is the hash. No filename_pattern needed.
#   2. Multi-file index (e.g. `SHA-256.txt`): caller passes a filename_pattern
#      and the matching row's first token is used.
#
# Deletes the downloaded file on any failure (network, parse error, mismatch),
# matching verify_checksum's behaviour so the caller never proceeds with an
# unverified payload.
#
# Usage:
#   verify_checksum_from_url "/path/to/file" "https://.../file.sha256"
#   verify_checksum_from_url "/path/to/file" "https://.../INDEX.txt" "file.zip"
verify_checksum_from_url() {
    local file="$1"
    local checksum_url="$2"
    local filename_pattern="${3:-}"

    if [ ! -f "$file" ]; then
        log_error "Cannot verify checksum: file not found: $file"
        return 1
    fi

    log_info "Fetching SHA-256 from $(basename "$checksum_url")..."
    local checksum_content
    if ! checksum_content=$(wget -qO- "$checksum_url"); then
        log_error "Could not retrieve checksum file from $checksum_url"
        rm -f "$file"
        return 1
    fi

    local expected
    if [ -n "$filename_pattern" ]; then
        expected=$(echo "$checksum_content" | grep -F "$filename_pattern" | awk '{print $1}' | head -1)
    else
        expected=$(echo "$checksum_content" | awk 'NR==1 {print $1}')
    fi

    if [ -z "$expected" ] || ! [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]]; then
        log_error "Could not parse a valid SHA-256 from $checksum_url"
        rm -f "$file"
        return 1
    fi

    verify_checksum "$file" "$expected"
}
