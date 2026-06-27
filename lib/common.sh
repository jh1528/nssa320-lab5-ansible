#!/usr/bin/env bash
# ==============================================================================
# common.sh
# ==============================================================================
#
# Shared output and safety helpers for NSSA320 Lab 5.
#
# Author:
#  - Jared Husson
#
# ==============================================================================
# Version History
# ==============================================================================
#
# Version: 5.0
# Date: 2026-06-26
#
# Changes:
#  - Reused the Lab 4 shared helper library as the Lab 5 baseline.
#  - Updated the source guard from LAB4_COMMON_SH_LOADED to LAB5_COMMON_SH_LOADED.
#  - Kept shared output, safety, and validation helpers for Lab 5 control node scripts.
#
# Notes:
#  - This file should be sourced by Lab 5 scripts instead of redefining output helpers.
#  - This file does not make configuration changes by itself.
#
# ==============================================================================


# ================================================================================
# Source Guard
# ================================================================================
#
# Purpose:
#  - Prevents this file from being loaded more than once in the same shell session.
#
# Notes:
#  - This is useful when multiple libraries source common.sh.
# ================================================================================

if [[ -n "${LAB5_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi

LAB5_COMMON_SH_LOADED="true"


# ================================================================================
# Color Initialization
# ================================================================================

init_colors() {
    if [[ -t 1 ]]; then
        RED=$'\033[0;31m'
        YELLOW=$'\033[1;33m'
        GREEN=$'\033[0;32m'
        BLUE=$'\033[0;34m'
        CYAN=$'\033[0;36m'
        BOLD=$'\033[1m'
        NC=$'\033[0m'
    else
        RED=""
        YELLOW=""
        GREEN=""
        BLUE=""
        CYAN=""
        BOLD=""
        NC=""
    fi
}


# ================================================================================
# General Output Helpers
# ================================================================================

step() {
    printf '\n%s%s==> %s%s\n' "$BOLD" "$CYAN" "$*" "$NC"
}

info() {
    printf '%s[INFO]%s %s\n' "$BLUE" "$NC" "$*"
}


# ================================================================================
# Check / Result Output Helpers
# ================================================================================

pass() {
    printf '%s[PASS]%s %s\n' "$GREEN" "$NC" "$*"
}

warn() {
    printf '%s[WARN]%s %s\n' "$YELLOW" "$NC" "$*"
}

fail() {
    printf '%s[FAIL]%s %s\n' "$RED" "$NC" "$*"
}

die() {
    fail "$*"
    exit 1
}


# ================================================================================
# Safety Helpers
# ================================================================================

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "This script must be run with sudo or as root."
    fi

    pass "Root privileges confirmed."
}

require_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        die "This script must be run as the normal student user, not with sudo."
    fi

    pass "Normal user execution confirmed."
}

require_command() {
    local command_name="$1"

    if command -v "$command_name" >/dev/null 2>&1; then
        pass "Required command found: ${command_name}"
    else
        die "Required command not found: ${command_name}"
    fi
}

require_file() {
    local file_path="$1"

    if [[ -f "$file_path" ]]; then
        pass "Required file found: ${file_path}"
    else
        die "Required file not found: ${file_path}"
    fi
}

require_directory() {
    local dir_path="$1"

    if [[ -d "$dir_path" ]]; then
        pass "Required directory found: ${dir_path}"
    else
        die "Required directory not found: ${dir_path}"
    fi
}

run_or_die() {
    local description="$1"
    shift

    info "$description"
    "$@" || die "Command failed: $description"
}


# ================================================================================
# Initialization
# ================================================================================

init_colors
