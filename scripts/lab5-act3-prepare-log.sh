#!/usr/bin/env bash
# ==============================================================================
# lab5-act3-prepare-log.sh
# ==============================================================================
#
# Activity 3 log preparation script for NSSA320 Lab 5.
#
# Purpose:
#  - Prepare a clean ansible.log before running Activity 3 manual commands
#  - Archive any existing ansible.log with a timestamp
#  - Confirm ansible.cfg is configured to write to ./ansible.log
#
# Design:
#  - This script does not run the Activity 3 Ansible commands.
#  - Activity 3 commands should still be run manually.
#  - This script only prepares the log file so evidence is clean.
#
# Author:
#  - Jared Husson
#
# ==============================================================================
# Version History
# ==============================================================================
#
# Version: 5.0
# Date: 2026-06-28
#
# Changes:
#  - Added first Activity 3 log preparation script.
#  - Added timestamped archive behavior for existing ansible.log.
#  - Added ansible.cfg log_path validation.
#
# ==============================================================================

set -u


# ==============================================================================
# Path Setup
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"


# ==============================================================================
# Load Shared Configuration and Libraries
# ==============================================================================

source "${BASE_DIR}/lib/common.sh"


# ==============================================================================
# Settings
# ==============================================================================

ANSIBLE_CFG="${BASE_DIR}/ansible.cfg"
ANSIBLE_LOG="${BASE_DIR}/ansible.log"
ARCHIVE_DIR="${BASE_DIR}/logs/archive"


# ==============================================================================
# Helpers
# ==============================================================================

validate_ansible_log_path() {
    step "Validating ansible.cfg log_path setting"

    require_file "$ANSIBLE_CFG"

    if grep -q '^log_path[[:space:]]*=[[:space:]]*\./ansible\.log' "$ANSIBLE_CFG"; then
        pass "ansible.cfg is configured to write to ./ansible.log"
        return 0
    fi

    fail "ansible.cfg does not contain: log_path = ./ansible.log"
    info "Run this first:"
    info "./scripts/lab5-act1-check.sh --apply-ansible-cfg"
    return 1
}

archive_existing_log() {
    local timestamp
    local archive_file

    step "Checking for existing ansible.log"

    mkdir -p "$ARCHIVE_DIR" || die "Failed to create archive directory: ${ARCHIVE_DIR}"

    if [[ ! -f "$ANSIBLE_LOG" ]]; then
        info "No existing ansible.log found."
        return 0
    fi

    if [[ ! -s "$ANSIBLE_LOG" ]]; then
        warn "Existing ansible.log is empty. Removing it before creating a fresh log."
        rm -f "$ANSIBLE_LOG" || die "Failed to remove empty ansible.log"
        return 0
    fi

    timestamp="$(date +%Y%m%d-%H%M%S)"
    archive_file="${ARCHIVE_DIR}/ansible-${timestamp}.log"

    info "Archiving existing ansible.log to:"
    info "$archive_file"

    mv "$ANSIBLE_LOG" "$archive_file" || die "Failed to archive existing ansible.log"

    pass "Existing ansible.log archived"
}

create_fresh_log() {
    step "Creating fresh ansible.log"

    touch "$ANSIBLE_LOG" || die "Failed to create ansible.log"

    pass "Fresh ansible.log created: ${ANSIBLE_LOG}"
}

show_log_status() {
    step "Activity 3 log status"

    info "Project directory: ${BASE_DIR}"
    info "Ansible config: ${ANSIBLE_CFG}"
    info "Active log file: ${ANSIBLE_LOG}"
    info "Archive directory: ${ARCHIVE_DIR}"

    ls -lh "$ANSIBLE_LOG" || warn "Unable to list ansible.log"

    pass "Log preparation completed"
    info "Now run Activity 3 commands manually so Ansible writes to ansible.log."
}


# ==============================================================================
# Main
# ==============================================================================

main() {
    cd "$BASE_DIR" || exit 1

    require_not_root

    validate_ansible_log_path || exit 1
    archive_existing_log
    create_fresh_log
    show_log_status
}

main "$@"
