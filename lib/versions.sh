#!/bin/bash
# shellcheck disable=SC2034  # URL/version vars are consumed by sourcing scripts

# =============================================================================
# VERSIONS LIBRARY
# =============================================================================
# Central registry for all versioned URLs and release identifiers.
# Source this file before downloading anything.
# To upgrade a tool, change only the VERSION variable — the URLs derive from it.
# =============================================================================

# Detect running Fedora release once; scripts use this for repo URLs
FEDORA_VERSION=$(rpm -E %fedora 2>/dev/null || echo "41")

# Each download below pairs its primary URL with a *_SHA256_URL pointing at
# the vendor-published checksum file. lib/verify.sh:verify_checksum_from_url
# fetches and parses these at runtime so version bumps don't strand a stale
# hash here.

# --- JetBrains IDEs ---
IDEA_VERSION="2026.2.1"
IDEA_FILENAME="idea-${IDEA_VERSION}.tar.gz"
IDEA_URL="https://download.jetbrains.com/idea/${IDEA_FILENAME}"
IDEA_SHA256_URL="${IDEA_URL}.sha256"

PYCHARM_VERSION="2026.2.1"
PYCHARM_FILENAME="pycharm-${PYCHARM_VERSION}.tar.gz"
PYCHARM_URL="https://download.jetbrains.com/python/${PYCHARM_FILENAME}"
PYCHARM_SHA256_URL="${PYCHARM_URL}.sha256"

# --- Gradle ---
GRADLE_VERSION="8.14.4"
GRADLE_FILENAME="gradle-${GRADLE_VERSION}-bin.zip"
GRADLE_URL="https://services.gradle.org/distributions/${GRADLE_FILENAME}"
GRADLE_SHA256_URL="${GRADLE_URL}.sha256"
GRADLE_HOME_DIR="gradle-${GRADLE_VERSION}"

# --- FiraCode Nerd Font ---
# nerd-fonts publishes one SHA-256.txt index per release covering every archive;
# verify_checksum_from_url's third arg picks the FiraCode.zip line out of it.
FIRACODE_VERSION="3.5.1"
FIRACODE_FILENAME="FiraCode.zip"
FIRACODE_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${FIRACODE_VERSION}/${FIRACODE_FILENAME}"
FIRACODE_SHA256_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${FIRACODE_VERSION}/SHA-256.txt"

# --- Wine ---
# Uses the detected Fedora release so the repo stays valid after upgrades
WINE_REPO_URL="https://dl.winehq.org/wine-builds/fedora/${FEDORA_VERSION}/winehq.repo"

# --- Oh My Posh ---
OMP_BIN_URL="https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64"
OMP_BIN_SHA256_URL="${OMP_BIN_URL}.sha256"
OMP_THEMES_URL="https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip"
OMP_THEMES_SHA256_URL="${OMP_THEMES_URL}.sha256"

# --- OpenJDK ---
OPENJDK_FILENAME="openjdk-21+35_linux-x64_bin.tar.gz"
OPENJDK_URL="https://download.java.net/openjdk/jdk21/ri/${OPENJDK_FILENAME}"
OPENJDK_SHA256_URL="${OPENJDK_URL}.sha256"
