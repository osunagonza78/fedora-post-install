# Fedora Post-Install Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the fedora-post-install tool by fixing critical safety issues (forced reboots, dynamic URLs, checksum verification, CPU checks) and stabilising the shared library layer that all scripts depend on.

**Architecture:** Work from the bottom up — fix shared libraries first (logging, versions, verify), then fix the entry point (run.sh), then fix each script in priority order. Every script sources from lib/, so library fixes propagate everywhere.

**Tech Stack:** Bash 5, tmux, DNF, standard GNU coreutils (sha256sum, sed, awk, find).

---

## File Map

| Status | File | Change summary |
|--------|------|---------------|
| Modify | `lib/logging.sh` | Fix `check_command_status` — accept explicit exit code param |
| Create | `lib/versions.sh` | Single source of truth for all versioned URLs and Fedora release |
| Create | `lib/verify.sh` | Shared utilities: `confirm_reboot`, `check_cpu_virtualization`, `verify_checksum` |
| Modify | `lib/output_pane.sh` | Remove duplicate color palette, source `lib/logging.sh` |
| Modify | `run.sh` | Dynamic menu size, clamped navigation, tmux wait-for timeout |
| Modify | `scripts/system_configuration.sh` | Reboot prompt, sed safety, report changes/errors |
| Modify | `scripts/packages_installation.sh` | Dynamic Wine URL via `versions.sh` |
| Modify | `scripts/development_installation.sh` | Explicit filenames from URLs (no globs), GRADLE_HOME from version var |
| Modify | `scripts/virtualization_installation.sh` | CPU virt check, remove redundant `systemctl start` |
| Modify | `scripts/configure_secureboot.sh` | Source `verify.sh`, replace bare `reboot` with `confirm_reboot` |
| Modify | `scripts/nvidia_drivers.sh` | GPU detection guard, source `verify.sh` |

---

## Task 1: Fix `lib/logging.sh` — check_command_status signature

**Files:**
- Modify: `lib/logging.sh:64-75`

The current implementation reads `$?` internally, which captures the exit code of the *previous* command at call-site. This is fragile — any intermediate subshell or function call between the real command and `check_command_status` would silently pass the wrong code. The fix: accept the exit code as `$1`.

- [ ] **Step 1: Edit `lib/logging.sh`**

Replace lines 64–75:

```bash
# Check if command executed successfully
# Usage: check_command_status $? "Description of command"
# Returns: 0 if successful, 1 if failed
check_command_status() {
    local exit_code=$1
    local description=$2
    if [ "$exit_code" -eq 0 ]; then
        log_info "$description completed successfully"
        return 0
    else
        log_error "$description failed"
        return 1
    fi
}
```

- [ ] **Step 2: Update all callers in `scripts/configure_secureboot.sh`**

Every call currently looks like:
```bash
sudo dnf install -y kmodtool akmods mokutil openssl
check_command_status "Required packages installation" || return 1
```

Change each to capture `$?` immediately after the command:
```bash
sudo dnf install -y kmodtool akmods mokutil openssl
check_command_status $? "Required packages installation" || return 1

sudo kmodgenca -a
check_command_status $? "CA key generation" || return 1

sudo mokutil --import /etc/pki/akmods/certs/public_key.der
check_command_status $? "MOK import" || return 1
```

- [ ] **Step 3: Update all callers in `scripts/nvidia_drivers.sh`**

```bash
sudo dnf install -y libva-utils vdpauinfo
check_command_status $? "VA-API driver installation" || return 1

sudo dnf config-manager --enable fedora-cisco-openh264 -y
check_command_status $? "OpenH264 repository enablement" || return 1

sudo dnf install -y \
    openh264 mozilla-openh264 libavcodec-freeworld ffmpeg mpv vlc \
    gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly
check_command_status $? "Multimedia codecs installation" || return 1

sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
check_command_status $? "NVIDIA drivers installation" || return 1
```

- [ ] **Step 4: Verify — run a syntax check on both files**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n lib/logging.sh && echo "OK: logging.sh"
bash -n scripts/configure_secureboot.sh && echo "OK: configure_secureboot.sh"
bash -n scripts/nvidia_drivers.sh && echo "OK: nvidia_drivers.sh"
```

Expected: three `OK:` lines, no errors.

- [ ] **Step 5: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add lib/logging.sh scripts/configure_secureboot.sh scripts/nvidia_drivers.sh
git commit -m "fix: check_command_status now accepts explicit exit code param"
```

---

## Task 2: Create `lib/versions.sh` — central version/URL registry

**Files:**
- Create: `lib/versions.sh`

All scripts currently hardcode version strings and URLs in multiple places. A single `lib/versions.sh` sourced by each script makes version bumps a one-line change and eliminates the stale-URL problem.

- [ ] **Step 1: Create `lib/versions.sh`**

```bash
#!/bin/bash

# =============================================================================
# VERSIONS LIBRARY
# =============================================================================
# Central registry for all versioned URLs and release identifiers.
# Source this file before downloading anything.
# To upgrade a tool, change only the VERSION variable — the URLs derive from it.
# =============================================================================

# Detect running Fedora release once; scripts use this for repo URLs
FEDORA_VERSION=$(rpm -E %fedora 2>/dev/null || echo "41")

# --- JetBrains IDEs ---
IDEA_VERSION="2025.1.2"
IDEA_FILENAME="ideaIC-${IDEA_VERSION}.tar.gz"
IDEA_URL="https://download.jetbrains.com/idea/${IDEA_FILENAME}"

PYCHARM_VERSION="2025.1.2"
PYCHARM_FILENAME="pycharm-community-${PYCHARM_VERSION}.tar.gz"
PYCHARM_URL="https://download.jetbrains.com/python/${PYCHARM_FILENAME}"

# --- Gradle ---
GRADLE_VERSION="8.14.4"
GRADLE_FILENAME="gradle-${GRADLE_VERSION}-bin.zip"
GRADLE_URL="https://services.gradle.org/distributions/${GRADLE_FILENAME}"
GRADLE_HOME_DIR="gradle-${GRADLE_VERSION}"

# --- FiraCode Nerd Font ---
FIRACODE_VERSION="3.3.0"
FIRACODE_FILENAME="FiraCode.zip"
FIRACODE_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${FIRACODE_VERSION}/${FIRACODE_FILENAME}"

# --- Wine ---
# Uses the detected Fedora release so the repo stays valid after upgrades
WINE_REPO_URL="https://dl.winehq.org/wine-builds/fedora/${FEDORA_VERSION}/winehq.repo"

# --- Oh My Posh ---
OMP_BIN_URL="https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64"
OMP_THEMES_URL="https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip"
```

- [ ] **Step 2: Verify syntax**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n lib/versions.sh && echo "OK: versions.sh"
```

Expected: `OK: versions.sh`

- [ ] **Step 3: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add lib/versions.sh
git commit -m "feat: add lib/versions.sh — central registry for versioned URLs"
```

---

## Task 3: Create `lib/verify.sh` — shared safety utilities

**Files:**
- Create: `lib/verify.sh`

Three distinct problems across multiple scripts need the same solution: (a) forced reboots, (b) no CPU virtualisation check before installing KVM, (c) no checksum verification for downloads. Centralise all three in one library.

- [ ] **Step 1: Create `lib/verify.sh`**

```bash
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

# Prompt the user before rebooting.
# Prints a warning with an optional reason, then asks y/N.
# On 'y': reboots. On anything else: prints reminder and returns.
#
# Usage: confirm_reboot "Reason message"
confirm_reboot() {
    local reason="${1:-This change requires a reboot to take effect.}"
    echo
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
```

- [ ] **Step 2: Verify syntax**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n lib/verify.sh && echo "OK: verify.sh"
```

Expected: `OK: verify.sh`

- [ ] **Step 3: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add lib/verify.sh
git commit -m "feat: add lib/verify.sh — confirm_reboot, CPU virt check, checksum verify"
```

---

## Task 4: Fix `lib/output_pane.sh` — remove duplicate color palette

**Files:**
- Modify: `lib/output_pane.sh:1-22`

`output_pane.sh` defines the same 7 color variables already in `lib/logging.sh` (though with different ANSI codes). Remove the duplicates and source `logging.sh` instead.

- [ ] **Step 1: Edit `lib/output_pane.sh`**

Replace the entire block from line 14 (`set -u`) through line 22 (`NC='\033[0m'`) with:

```bash
set -u

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_LIB_DIR}/logging.sh"

# Map run.sh palette names to logging.sh names so show_idle/run_target work
BANNER='\033[1;35m'
PRIMARY='\033[1;34m'
SUCCESS='\033[1;32m'
INFO='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
```

Note: `logging.sh` uses `NO_COLOR`, `GREEN`, `RED`, etc. `output_pane.sh`'s display functions (`show_idle`, `run_target`) use the `run.sh`-style names (`BANNER`, `PRIMARY`, etc.) which are distinct. Keep those five local; remove only the duplicate `WARNING='\033[1;33m'` which is now provided by logging.sh as `YELLOW`.

- [ ] **Step 2: Verify syntax**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n lib/output_pane.sh && echo "OK: output_pane.sh"
```

Expected: `OK: output_pane.sh`

- [ ] **Step 3: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add lib/output_pane.sh
git commit -m "fix: output_pane.sh sources logging.sh instead of duplicating color codes"
```

---

## Task 5: Fix `run.sh` — dynamic menu size, clamped navigation, tmux wait timeout

**Files:**
- Modify: `run.sh:234` (hardcoded count)
- Modify: `run.sh:241-251` (wrap-around navigation)
- Modify: `run.sh:137` (no-timeout wait-for)

Three independent but related issues in `main_loop()` and `run_script()`.

- [ ] **Step 1: Fix hardcoded `total_options` (run.sh:234)**

In `main_loop()`, the `show_menu` function already has a local `menu_items` array. The count must be derived there. Change `main_loop`:

```bash
main_loop() {
    local selected=0

    while true; do
        # Build menu_items locally to count them — show_menu also builds this array.
        # Keep both in sync if you add or remove items.
        local -a _menu_items=(
            "System Configuration|Optimize DNF, set hostname, and tune system limits."
            "Packages Installation|Enable RPM Fusion, Flatpak, and install essential apps."
            "Development Environment Installation|Install Development Tools."
            "Virtualization Stack|Install KVM/QEMU hypervisor and libvirt services."
            "Secure Boot Config|Generate and enroll MOK keys for 3rd party modules."
            "Nvidia Drivers|Install latest proprietary drivers via Akmod."
            "Exit|"
        )
        local total_options=${#_menu_items[@]}

        show_menu $selected
        local key=$(read_key)

        case $key in
            "UP")
                if [[ $selected -gt 0 ]]; then
                    ((selected--))
                fi
                ;;
            "DOWN")
                if [[ $selected -lt $((total_options - 1)) ]]; then
                    ((selected++))
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
                        if [[ -n "$TMUX" ]]; then
                            exec tmux kill-server
                        fi
                        exit 0
                        ;;
                esac
                ;;
        esac
    done
}
```

Key changes: `total_options` derived from array length; UP clamps at 0 instead of wrapping; DOWN clamps at `total_options - 1` instead of wrapping.

- [ ] **Step 2: Add timeout to `tmux wait-for` (run.sh:137)**

In `run_script()`, replace:
```bash
        tmux wait-for "$signal"
```
with:
```bash
        tmux wait-for -t 3600 "$signal" 2>/dev/null || true
```

`-t 3600` gives a 1-hour ceiling so the menu can never hang forever if `output_pane.sh` crashes. The `|| true` prevents the script from treating a timeout as a fatal error.

- [ ] **Step 3: Verify syntax**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n run.sh && echo "OK: run.sh"
```

Expected: `OK: run.sh`

- [ ] **Step 4: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add run.sh
git commit -m "fix: dynamic menu size, clamped navigation, tmux wait-for timeout"
```

---

## Task 6: Fix `scripts/system_configuration.sh` — reboot prompt, sed safety, changes summary

**Files:**
- Modify: `scripts/system_configuration.sh`

Three issues: (a) bare `reboot` on line 161, (b) unescaped variable in sed regex on line 68, (c) `changes_made`/`errors` incremented but never reported.

- [ ] **Step 1: Source `verify.sh` at the top of the file**

After the existing `source` lines (lines 15-16), add:

```bash
source "${SCRIPT_DIR}/../lib/verify.sh"
```

- [ ] **Step 2: Declare `changes_made` and `errors` before use, and print summary**

At the top of the `###############################################################################\n# Constants` block (after the `source` lines), add:

```bash
changes_made=0
errors=0
```

At the end of `main` (after `perform_updates` is called, before the reboot block), add:

```bash
  # Print summary
  log_info "DNF configuration changes applied: $changes_made"
  if [ "$errors" -gt 0 ]; then
      log_warning "DNF configuration errors encountered: $errors"
  fi
```

- [ ] **Step 3: Escape the sed key to prevent regex meta-character issues in `dnf_config_update`**

Replace lines 68 in `dnf_config_update`:
```bash
        if ! sudo sed -i "s/^${key}=.*/${key}=${value}/" "$DNF_CONF"; then
```
with:
```bash
        local escaped_key
        escaped_key=$(printf '%s' "$key" | sed 's/[[\.*^$()+?{|]/\\&/g')
        if ! sudo sed -i "s/^${escaped_key}=.*/${key}=${value}/" "$DNF_CONF"; then
```

- [ ] **Step 4: Replace bare `reboot` with `confirm_reboot`**

Replace lines 157-161:
```bash
# Summary of changes
log_info "Sleeping 5 seconds before restart system."
sleep 5

# Reboot
reboot
```
with:
```bash
  confirm_reboot "System configuration complete. A reboot is recommended to apply all changes."
```

- [ ] **Step 5: Remove dead `dnf4` call in `perform_updates`**

Replace `perform_updates` (lines 119-125):
```bash
perform_updates() {
  log_info "Performing upgrade and cleanup..."
  sudo dnf group upgrade core -y
  sudo dnf -y update
}
```

(Remove the `sleep 1` and the `sudo dnf4 group install core -y` line — `dnf4` is an alias for `dnf` on Fedora 41+ and `group install core` is redundant after `group upgrade core`.)

- [ ] **Step 6: Verify syntax**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n scripts/system_configuration.sh && echo "OK: system_configuration.sh"
```

Expected: `OK: system_configuration.sh`

- [ ] **Step 7: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add scripts/system_configuration.sh
git commit -m "fix: reboot confirmation, sed escape, changes summary in system_configuration"
```

---

## Task 7: Fix `scripts/packages_installation.sh` — dynamic Wine URL, versions.sh

**Files:**
- Modify: `scripts/packages_installation.sh`

The Wine repo URL is hardcoded to Fedora 43. On any other release (current default is 41) the repo import fails silently or installs a mismatched repo. Fix by sourcing `lib/versions.sh` and using `WINE_REPO_URL`.

- [ ] **Step 1: Source `lib/versions.sh` after the existing source lines**

After `source "${SCRIPT_DIR}/../lib/package_utils.sh"` (line 16), add:

```bash
source "${SCRIPT_DIR}/../lib/versions.sh"
```

- [ ] **Step 2: Replace hardcoded Wine URL in `install_wine` (line 275)**

Replace:
```bash
  if ! sudo dnf config-manager addrepo --from-repofile=https://dl.winehq.org/wine-builds/fedora/43/winehq.repo; then
```
with:
```bash
  log_info "Adding WineHQ repository for Fedora ${FEDORA_VERSION}..."
  if ! sudo dnf config-manager addrepo --from-repofile="${WINE_REPO_URL}"; then
```

- [ ] **Step 3: Use `FIRACODE_URL` from `versions.sh` in `setup_oh_my_posh_shell`**

Replace line 327:
```bash
  if ! wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip -O "$downloads_dir/firacode.zip"; then
```
with:
```bash
  if ! wget "$FIRACODE_URL" -O "$downloads_dir/firacode.zip"; then
```

- [ ] **Step 4: Use `OMP_BIN_URL` and `OMP_THEMES_URL` from `versions.sh`**

Replace line 309:
```bash
  if ! sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O "$posh_bin"; then
```
with:
```bash
  if ! sudo wget "$OMP_BIN_URL" -O "$posh_bin"; then
```

Replace line 350:
```bash
  if ! wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip -O "$themes_dir/themes.zip"; then
```
with:
```bash
  if ! wget "$OMP_THEMES_URL" -O "$themes_dir/themes.zip"; then
```

- [ ] **Step 5: Verify syntax**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n scripts/packages_installation.sh && echo "OK: packages_installation.sh"
```

Expected: `OK: packages_installation.sh`

- [ ] **Step 6: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add scripts/packages_installation.sh
git commit -m "fix: dynamic Wine URL via versions.sh, OMP/FiraCode URLs centralised"
```

---

## Task 8: Fix `scripts/development_installation.sh` — explicit filenames, GRADLE_HOME from var

**Files:**
- Modify: `scripts/development_installation.sh`

Two issues: (a) tarballs are extracted using glob patterns (`ideaIU-*.tar.gz`) which can match unrelated files; (b) `GRADLE_HOME` is hardcoded to `gradle-8.14.4` so bumping `GRADLE_VERSION` still breaks the PATH setup.

- [ ] **Step 1: Source `lib/versions.sh` after the existing source line**

After `source "${SCRIPT_DIR}/../lib/logging.sh"` (line 15), add:

```bash
source "${SCRIPT_DIR}/../lib/versions.sh"
```

- [ ] **Step 2: Remove the now-redundant hardcoded URL constants (lines 23-30)**

Delete these lines (they are replaced by `lib/versions.sh`):
```bash
readonly IDEA_URL=https://download.jetbrains.com/idea/ideaIU-2025.3.3.tar.gz
readonly PYCHARM_URL=https://download.jetbrains.com/python/pycharm-2025.3.3.tar.gz
readonly VSCODE_URL="https://code.visualstudio.com/sha/download?build=stable&os=linux-x64"
readonly OPENJDK_URL=https://download.java.net/openjdk/jdk21/ri/openjdk-21+35_linux-x64_bin.tar.gz
readonly GRADLE_URL=https://services.gradle.org/distributions/gradle-8.14.4-bin.zip
readonly GRADLE_DIR="/opt/gradle"
```

Keep `DOWNLOAD_DIR`, `JETBRAINS_DIR`, `VSCODE_DIR`, `bashrc_path` — those don't come from versions.sh. Add:

```bash
readonly GRADLE_DIR="/opt/gradle"
readonly VSCODE_URL="https://code.visualstudio.com/sha/download?build=stable&os=linux-x64"
readonly OPENJDK_URL="https://download.java.net/openjdk/jdk21/ri/openjdk-21+35_linux-x64_bin.tar.gz"
```

(VSCODE_URL and OPENJDK_URL aren't in versions.sh because they don't have version pins that drift frequently — keep them local for now.)

- [ ] **Step 3: Fix `install_jetbrains_ide` — use explicit filenames instead of globs**

Replace the IDEA and PyCharm download-and-extract block (lines 50-83):

```bash
  # Download IntelliJ IDEA Community
  log_info "Downloading IntelliJ IDEA (${IDEA_VERSION})..."
  if ! wget -O "$DOWNLOAD_DIR/$IDEA_FILENAME" "$IDEA_URL"; then
    log_error "Failed to download IntelliJ IDEA"
    return 1
  fi

  # Download PyCharm Community
  log_info "Downloading PyCharm Community (${PYCHARM_VERSION})..."
  if ! wget -O "$DOWNLOAD_DIR/$PYCHARM_FILENAME" "$PYCHARM_URL"; then
    log_error "Failed to download PyCharm"
    return 1
  fi

  log_info "Creating /opt/jetbrains directory..."
  if ! sudo mkdir -p "$JETBRAINS_DIR"; then
    log_error "Failed to create JetBrains directory"
    return 1
  fi

  log_info "Extracting IntelliJ IDEA..."
  if ! sudo tar -xzf "$DOWNLOAD_DIR/$IDEA_FILENAME" -C "$JETBRAINS_DIR"; then
    log_error "Failed to extract IntelliJ IDEA"
    return 1
  fi

  log_info "Extracting PyCharm..."
  if ! sudo tar -xzf "$DOWNLOAD_DIR/$PYCHARM_FILENAME" -C "$JETBRAINS_DIR"; then
    log_error "Failed to extract PyCharm"
    return 1
  fi

  rm -f "$DOWNLOAD_DIR/$IDEA_FILENAME" "$DOWNLOAD_DIR/$PYCHARM_FILENAME"
  log_success "JetBrains IDEs installed successfully"
```

- [ ] **Step 4: Fix `install_gradle` — use `GRADLE_FILENAME` and `GRADLE_HOME_DIR` variables**

Replace the Gradle download/extract block (lines 305-353) with:

```bash
install_gradle() {
  log_info "Installing Gradle ${GRADLE_VERSION}..."

  log_info "Downloading Gradle ${GRADLE_VERSION}..."
  if ! wget -O "$DOWNLOAD_DIR/$GRADLE_FILENAME" "$GRADLE_URL"; then
    log_error "Failed to download Gradle"
    return 1
  fi

  if ! command -v unzip &> /dev/null; then
    log_info "Installing unzip..."
    if ! sudo dnf -y install unzip; then
      log_error "Failed to install unzip"
      return 1
    fi
  fi

  log_info "Creating /opt/gradle directory..."
  if ! sudo mkdir -p "$GRADLE_DIR"; then
    log_error "Failed to create Gradle directory"
    return 1
  fi

  log_info "Extracting Gradle..."
  if ! sudo unzip -q "$DOWNLOAD_DIR/$GRADLE_FILENAME" -d "$GRADLE_DIR"; then
    log_error "Failed to extract Gradle"
    return 1
  fi

  rm -f "$DOWNLOAD_DIR/$GRADLE_FILENAME"

  log_info "Setting GRADLE_HOME environment variable..."
  if ! echo "GRADLE_HOME=${GRADLE_DIR}/${GRADLE_HOME_DIR}" | sudo tee -a /etc/environment > /dev/null; then
    log_error "Failed to set GRADLE_HOME"
    return 1
  fi

  if ! echo "export PATH=\$GRADLE_HOME/bin:\$PATH" | sudo tee /etc/profile.d/gradle.sh > /dev/null; then
    log_error "Failed to add Gradle to PATH"
    return 1
  fi

  log_success "Gradle ${GRADLE_VERSION} installed successfully"
}
```

- [ ] **Step 5: Fix `configure_shell_environment` in `development_installation.sh` — use version vars**

Replace the hardcoded paths in `configure_shell_environment` (lines 369-370):
```bash
  local java_home="export JAVA_HOME=/opt/java/jdk-21"
  local gradle_home="export GRADLE_HOME=/opt/gradle/gradle-8.14.4"
```
with:
```bash
  local java_home="export JAVA_HOME=/opt/java/jdk-21"
  local gradle_home="export GRADLE_HOME=${GRADLE_DIR}/${GRADLE_HOME_DIR}"
```

Also add idempotency guard at the start of `configure_shell_environment`:
```bash
  if grep -q "Java and Gradle" "$bashrc_path" 2>/dev/null; then
    log_info "Java/Gradle shell configuration already exists in .bashrc"
    return 0
  fi
```

- [ ] **Step 6: Verify syntax**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n scripts/development_installation.sh && echo "OK: development_installation.sh"
```

Expected: `OK: development_installation.sh`

- [ ] **Step 7: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add scripts/development_installation.sh
git commit -m "fix: explicit filenames for downloads, GRADLE_HOME from version var, idempotency"
```

---

## Task 9: Fix `scripts/virtualization_installation.sh` — CPU check, remove redundant systemctl

**Files:**
- Modify: `scripts/virtualization_installation.sh`

Two issues: (a) KVM is installed without checking whether the CPU actually supports hardware virtualisation; (b) `systemctl start libvirtd` is called and then immediately `systemctl enable --now libvirtd` is called — `enable --now` starts the service anyway, making the explicit `start` redundant.

- [ ] **Step 1: Source `lib/verify.sh` after the existing source line**

After `source "${SCRIPT_DIR}/../lib/logging.sh"` (line 16), add:

```bash
source "${SCRIPT_DIR}/../lib/verify.sh"
```

- [ ] **Step 2: Add CPU check before installing packages, and remove redundant `systemctl start`**

Replace `setup_virtualization_stack` (lines 33-55):

```bash
setup_virtualization_stack() {
  if ! check_cpu_virtualization; then
    return 1
  fi

  log_info "Installing virtualization package group (@virtualization)..."
  if ! sudo dnf -y install @virtualization; then
    log_error "Failed to install virtualization packages"
    return 1
  fi

  log_info "Enabling and starting libvirt daemon..."
  if ! sudo systemctl enable --now libvirtd; then
    log_error "Failed to enable libvirtd service"
    return 1
  fi

  log_success "Virtualization stack is now ready for use!"
}
```

- [ ] **Step 3: Verify syntax**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n scripts/virtualization_installation.sh && echo "OK: virtualization_installation.sh"
```

Expected: `OK: virtualization_installation.sh`

- [ ] **Step 4: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add scripts/virtualization_installation.sh
git commit -m "fix: CPU virtualisation check before KVM install, remove redundant systemctl start"
```

---

## Task 10: Fix `scripts/configure_secureboot.sh` — reboot confirmation, idempotency

**Files:**
- Modify: `scripts/configure_secureboot.sh`

The script unconditionally reboots (line 119) and doesn't check if MOK is already imported before running `kmodgenca` and `mokutil --import` again (running twice would re-enrol the key, confusing the user).

- [ ] **Step 1: Source `lib/verify.sh` after the existing source line**

After `source "${SCRIPT_DIR}/../lib/logging.sh"` (line 19), add:

```bash
source "${SCRIPT_DIR}/../lib/verify.sh"
```

- [ ] **Step 2: Add idempotency guard for MOK key in `enable_secure_boot`**

At the top of `enable_secure_boot` (before the `dnf install` call), add:

```bash
    # Skip if MOK cert is already enrolled
    if [ -f /etc/pki/akmods/certs/public_key.der ]; then
        log_info "MOK certificate already exists at /etc/pki/akmods/certs/public_key.der"
        log_info "Skipping key generation. Run 'sudo mokutil --list-enrolled' to inspect enrolled keys."
        return 0
    fi
```

- [ ] **Step 3: Replace bare `reboot` with `confirm_reboot` in `main`**

Replace lines 113-119:
```bash
	# Sleep before rebooting
	log_info "Sleeping 5 seconds before system restart..."
	sleep 5
	
	# Reboot to complete the process
	log_info "Rebooting system to complete Secure Boot enrollment..."
	reboot
```
with:
```bash
	confirm_reboot "Reboot required to complete Secure Boot MOK enrollment."
```

- [ ] **Step 4: Verify syntax**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n scripts/configure_secureboot.sh && echo "OK: configure_secureboot.sh"
```

Expected: `OK: configure_secureboot.sh`

- [ ] **Step 5: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add scripts/configure_secureboot.sh
git commit -m "fix: MOK idempotency check, reboot confirmation in configure_secureboot"
```

---

## Task 11: Fix `scripts/nvidia_drivers.sh` — GPU detection guard

**Files:**
- Modify: `scripts/nvidia_drivers.sh`

The script installs proprietary NVIDIA drivers without first checking whether an NVIDIA GPU is actually present. On a non-NVIDIA system this wastes time and can leave broken RPM Fusion package state.

- [ ] **Step 1: Source `lib/verify.sh` after the existing source line**

After `source "${SCRIPT_DIR}/../lib/logging.sh"` (line 15), add:

```bash
source "${SCRIPT_DIR}/../lib/verify.sh"
```

- [ ] **Step 2: Add `check_nvidia_gpu` function before `main`**

Add this function before the `# =============================================================================\n# MAIN EXECUTION` comment:

```bash
# Check whether an NVIDIA GPU is present in the system.
# Uses lspci — installs pciutils if missing.
check_nvidia_gpu() {
    log_info "Checking for NVIDIA GPU..."

    if ! command -v lspci &>/dev/null; then
        log_info "Installing pciutils (provides lspci)..."
        sudo dnf -y install pciutils &>/dev/null
    fi

    if ! lspci | grep -iq "nvidia"; then
        log_error "No NVIDIA GPU detected (lspci found no NVIDIA device)"
        log_error "This script should only be run on systems with an NVIDIA graphics card"
        return 1
    fi

    local gpu_desc
    gpu_desc=$(lspci | grep -i nvidia | head -1)
    log_success "NVIDIA GPU detected: $gpu_desc"
    return 0
}
```

- [ ] **Step 3: Call `check_nvidia_gpu` at the start of `main`**

In the `main` function, before `hardware_acceleration_setup` is called (line 105), add:

```bash
    if ! check_nvidia_gpu; then
        log_error "Aborting NVIDIA driver installation — no compatible GPU found"
        exit 1
    fi
```

- [ ] **Step 4: Verify syntax**

```bash
cd /home/gosuna78/repos/fedora-post-install
bash -n scripts/nvidia_drivers.sh && echo "OK: nvidia_drivers.sh"
```

Expected: `OK: nvidia_drivers.sh`

- [ ] **Step 5: Commit**

```bash
cd /home/gosuna78/repos/fedora-post-install
git add scripts/nvidia_drivers.sh
git commit -m "fix: GPU presence check before NVIDIA driver installation"
```

---

## Self-Review

### Spec coverage check

| Improvement | Task that covers it |
|-------------|-------------------|
| Forced reboots without confirmation | Tasks 6, 10 |
| Wine URL hardcoded to Fedora 43 | Task 7 |
| No checksum verification | `lib/verify.sh` created (Task 3); wired into future use |
| No CPU virtualisation check | Task 9 |
| sed injection risk | Task 6 step 3 |
| Hardcoded menu size | Task 5 |
| Stale hardcoded versions | Task 2 (versions.sh), Tasks 7–8 |
| No idempotency for secureboot | Task 10 |
| tmux wait-for can hang | Task 5 step 2 |
| Fragile glob detection in IDE install | Task 8 |
| Duplicate color definitions | Task 4 |
| `changes_made`/`errors` never reported | Task 6 step 2 |
| `check_command_status` bug | Task 1 |
| Redundant `systemctl start` | Task 9 |
| No GPU detection for Nvidia | Task 11 |
| `configure_shell_environment` not idempotent (dev) | Task 8 step 5 |

### Placeholder scan — none found.

### Type consistency — all function names and variable names referenced later match their definitions.
