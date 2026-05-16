#!/bin/bash
# shellcheck disable=SC2034  # palette vars are consumed by sourcing scripts

# =============================================================================
# UI LIBRARY
# =============================================================================
# Single source of truth for terminal colour codes and text-style modifiers.
# Sourced by lib/logging.sh, lib/output_pane.sh, and run.sh so the three
# previous parallel definitions don't drift.
#
# Two naming layers:
#   - Semantic (PRIMARY, SUCCESS, etc.)   — preferred for new code
#   - Legacy colour names (RED, GREEN…)   — kept so log_* and existing call
#                                            sites compile without churn.
# =============================================================================

# --- Semantic palette ---
PRIMARY='\033[1;34m'       # Bold Blue   — headings, separators
BANNER='\033[1;35m'        # Bold Magenta — top-of-pane banners
SUCCESS='\033[1;32m'       # Bold Green  — completion / done markers
WARNING='\033[1;33m'       # Bold Yellow — non-fatal warnings
DANGER='\033[1;31m'        # Bold Red    — fatal errors, prompts
INFO='\033[0;36m'          # Cyan        — informational lines, hints

# --- Modifiers ---
BOLD='\033[1m'
HIGHLIGHT='\033[7m'        # Reverse video — selected menu item
NC='\033[0m'               # No colour / reset

# --- Legacy colour names kept for back-compat ---
RED='\e[1;91m'
GREEN='\e[1;92m'
BLUE='\e[1;94m'
ORANGE='\e[1;93m'
YELLOW='\e[1;33m'
NO_COLOR='\e[0m'
