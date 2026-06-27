#!/usr/bin/env bash
# ==============================================================================
# ansiblecfg.sh
# ==============================================================================
#
# Shared Ansible configuration helpers for NSSA320 Lab 5.
#
# Purpose:
#  - Validate that ansible.cfg includes the Lab 5 required settings
#  - Write a clean Lab 5 ansible.cfg when requested
#  - Keep ansible.cfg generation idempotent and backed up
#  - Follow the Lab 5 assignment format for inventory, user, become, and logging
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Check functions do not change files.
#  - Apply functions intentionally rewrite ansible.cfg.
#  - Existing ansible.cfg is backed up before being rewritten.
#
# Author:
#  - Jared Husson
#
# ==============================================================================
# Version History
# ==============================================================================
#
# Version: 5.0
# Date: 2026-06-27
#
# Changes:
#  - Added Lab 5 ansible.cfg validation helpers.
#  - Added idempotent ansible.cfg writer.
#  - Added backup behavior before rewriting ansible.cfg.
#  - Matched the Lab 5 assignment settings for inventory, student user,
#    privilege escalation, host key checking, and Ansible logging.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================

if [[ -n "${LAB5_ANSIBLECFG_SH_LOADED:-}" ]]; then
    return 0
fi

LAB5_ANSIBLECFG_SH_LOADED="true"


# ==============================================================================
# ansible.cfg Helpers
# ==============================================================================

backup_ansible_cfg_file() {
    local cfg_file="${1:-./ansible.cfg}"
    local backup_file

    if [[ ! -f "$cfg_file" ]]; then
        warn "Ansible config file does not exist yet: ${cfg_file}"
        return 0
    fi

    backup_file="${cfg_file}.bak.$(date +%Y%m%d-%H%M%S)"

    info "Backing up ${cfg_file} to ${backup_file}"
    cp "$cfg_file" "$backup_file" || die "Failed to back up ${cfg_file}"

    pass "Backup created: ${backup_file}"
}

write_lab5_ansible_cfg_file() {
    local cfg_file="${1:-./ansible.cfg}"

    step "Writing Lab 5 ansible.cfg"

    backup_ansible_cfg_file "$cfg_file"

    cat > "$cfg_file" <<EOF
[defaults]
inventory = ./inventory.inv
remote_user = student
ansible_become = true
ansible_user = student
host_key_checking = false
log_path = ./ansible.log
EOF

    pass "Lab 5 ansible.cfg written: ${cfg_file}"
}

validate_lab5_ansible_cfg_file() {
    local cfg_file="${1:-./ansible.cfg}"
    local failed=0

    step "Validating Lab 5 ansible.cfg"

    if [[ ! -f "$cfg_file" ]]; then
        fail "Ansible config file is missing: ${cfg_file}"
        return 1
    fi

    grep -q '^\[defaults\]' "$cfg_file" \
        && pass "Found [defaults]" \
        || { fail "Missing [defaults]"; failed=1; }

    grep -q '^inventory[[:space:]]*=[[:space:]]*\./inventory\.inv' "$cfg_file" \
        && pass "Found inventory = ./inventory.inv" \
        || { fail "Missing inventory = ./inventory.inv"; failed=1; }

    grep -q '^remote_user[[:space:]]*=[[:space:]]*student' "$cfg_file" \
        && pass "Found remote_user = student" \
        || { fail "Missing remote_user = student"; failed=1; }

    grep -q '^ansible_become[[:space:]]*=[[:space:]]*true' "$cfg_file" \
        && pass "Found ansible_become = true" \
        || { fail "Missing ansible_become = true"; failed=1; }

    grep -q '^ansible_user[[:space:]]*=[[:space:]]*student' "$cfg_file" \
        && pass "Found ansible_user = student" \
        || { fail "Missing ansible_user = student"; failed=1; }

    grep -q '^host_key_checking[[:space:]]*=[[:space:]]*false' "$cfg_file" \
        && pass "Found host_key_checking = false" \
        || { fail "Missing host_key_checking = false"; failed=1; }

    grep -q '^log_path[[:space:]]*=[[:space:]]*\./ansible\.log' "$cfg_file" \
        && pass "Found log_path = ./ansible.log" \
        || { fail "Missing log_path = ./ansible.log"; failed=1; }

    if (( failed == 0 )); then
        pass "Lab 5 ansible.cfg validation passed"
        return 0
    else
        fail "Lab 5 ansible.cfg validation failed"
        info "Run this to converge ansible.cfg:"
        info "./scripts/lab5-act1-check.sh --apply-ansible-cfg"
        return 1
    fi
}
