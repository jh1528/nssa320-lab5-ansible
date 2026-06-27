#!/usr/bin/env bash
# ==============================================================================
# inventory.sh
# ==============================================================================
#
# Shared Ansible inventory helpers for NSSA320 Lab 5.
#
# Purpose:
#  - Validate that inventory.inv includes the Lab 5 Linux and Windows hosts
#  - Write a clean Lab 5 inventory from config/lab5.conf when requested
#  - Keep inventory generation idempotent and based on one source of truth
#  - Preserve Linux Ansible groups while adding the Windows WinRM host
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Check functions do not change files.
#  - Apply functions intentionally rewrite inventory.inv from config/lab5.conf.
#  - Existing inventory.inv is backed up before being rewritten.
#
# Author:
#  - Jared Husson
#
# ==============================================================================
# Version History
# ==============================================================================
#
# Version: 5.1
# Date: 2026-06-27
#
# Changes:
#  - Updated Windows host entry to match the Lab 5 instruction style.
#  - Kept all Linux Ansible hosts and groups in the generated inventory.
#  - Kept Windows WinRM variables in [windows:vars].
#  - Removed ansible_host from win11 so hostname resolution uses /etc/hosts.
#
# Version: 5.0
# Date: 2026-06-27
#
# Changes:
#  - Added Lab 5 inventory validation helpers.
#  - Added idempotent inventory writer based on config/lab5.conf.
#  - Added Windows WinRM inventory variables for win11.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================

if [[ -n "${LAB5_INVENTORY_SH_LOADED:-}" ]]; then
    return 0
fi

LAB5_INVENTORY_SH_LOADED="true"


# ==============================================================================
# Inventory Helpers
# ==============================================================================

backup_inventory_file() {
    local inventory_file="${1:-./inventory.inv}"
    local backup_file

    if [[ ! -f "$inventory_file" ]]; then
        warn "Inventory file does not exist yet: ${inventory_file}"
        return 0
    fi

    backup_file="${inventory_file}.bak.$(date +%Y%m%d-%H%M%S)"

    info "Backing up ${inventory_file} to ${backup_file}"
    cp "$inventory_file" "$backup_file" || die "Failed to back up ${inventory_file}"

    pass "Backup created: ${backup_file}"
}

write_lab5_inventory_file() {
    local inventory_file="${1:-./inventory.inv}"

    step "Writing Lab 5 inventory file"

    backup_inventory_file "$inventory_file"

    cat > "$inventory_file" <<EOF
# ==============================================================================
# NSSA320 Lab 5 - Ansible Inventory
# ==============================================================================
#
# Managed by Lab 5 inventory helper.
# Source of truth: config/lab5.conf
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Linux groups from Lab 4
# ------------------------------------------------------------------------------

[ubuntu_hosts]
${UBUNTU_HOST}

[rocky_hosts]
${ANSIBLE1_HOST}
${ANSIBLE2_HOST}

[linux:children]
ubuntu_hosts
rocky_hosts

[linux:vars]
ansible_user = ${LAB_USER}
ansible_connection = ssh
ansible_python_interpreter = /usr/bin/python3


# ------------------------------------------------------------------------------
# Windows group for Lab 5
# ------------------------------------------------------------------------------

[windows]
${WIN11_HOST}

[windows:vars]
ansible_user = ${ANSIBLE_SERVICE_USER}
ansible_password = Password1
ansible_connection = winrm
ansible_port = ${WINRM_PORT}
ansible_winrm_transport = ${WINRM_TRANSPORT}
ansible_winrm_server_cert_validation = ignore


# ------------------------------------------------------------------------------
# All managed hosts
# ------------------------------------------------------------------------------

[managed:children]
linux
windows
EOF

    pass "Lab 5 inventory file written: ${inventory_file}"
}

validate_lab5_inventory_file() {
    local inventory_file="${1:-./inventory.inv}"
    local failed=0

    step "Validating Lab 5 inventory file"

    if [[ ! -f "$inventory_file" ]]; then
        fail "Inventory file is missing: ${inventory_file}"
        return 1
    fi

    info "Checking required inventory groups"

    grep -q '^\[ubuntu_hosts\]' "$inventory_file" && pass "Found [ubuntu_hosts]" || { fail "Missing [ubuntu_hosts]"; failed=1; }
    grep -q '^\[rocky_hosts\]' "$inventory_file" && pass "Found [rocky_hosts]" || { fail "Missing [rocky_hosts]"; failed=1; }
    grep -q '^\[linux:children\]' "$inventory_file" && pass "Found [linux:children]" || { fail "Missing [linux:children]"; failed=1; }
    grep -q '^\[linux:vars\]' "$inventory_file" && pass "Found [linux:vars]" || { fail "Missing [linux:vars]"; failed=1; }
    grep -q '^\[windows\]' "$inventory_file" && pass "Found [windows]" || { fail "Missing [windows]"; failed=1; }
    grep -q '^\[windows:vars\]' "$inventory_file" && pass "Found [windows:vars]" || { fail "Missing [windows:vars]"; failed=1; }
    grep -q '^\[managed:children\]' "$inventory_file" && pass "Found [managed:children]" || { fail "Missing [managed:children]"; failed=1; }

    info "Checking required Linux hosts"

    grep -q "^${UBUNTU_HOST}$" "$inventory_file" && pass "Found ${UBUNTU_HOST}" || { fail "Missing ${UBUNTU_HOST}"; failed=1; }
    grep -q "^${ANSIBLE1_HOST}$" "$inventory_file" && pass "Found ${ANSIBLE1_HOST}" || { fail "Missing ${ANSIBLE1_HOST}"; failed=1; }
    grep -q "^${ANSIBLE2_HOST}$" "$inventory_file" && pass "Found ${ANSIBLE2_HOST}" || { fail "Missing ${ANSIBLE2_HOST}"; failed=1; }

    info "Checking required Windows host"

    grep -q "^${WIN11_HOST}$" "$inventory_file" && pass "Found ${WIN11_HOST}" || { fail "Missing ${WIN11_HOST}"; failed=1; }

    info "Checking Linux inventory variables"

    grep -q "^ansible_user[[:space:]]*=[[:space:]]*${LAB_USER}" "$inventory_file" && pass "Found Linux ansible_user ${LAB_USER}" || { fail "Missing Linux ansible_user ${LAB_USER}"; failed=1; }
    grep -q '^ansible_connection[[:space:]]*=[[:space:]]*ssh' "$inventory_file" && pass "Found Linux SSH connection setting" || { fail "Missing Linux ansible_connection ssh"; failed=1; }

    info "Checking Windows WinRM inventory variables"

    grep -q "^ansible_user[[:space:]]*=[[:space:]]*${ANSIBLE_SERVICE_USER}" "$inventory_file" && pass "Found Windows ansible_user ${ANSIBLE_SERVICE_USER}" || { fail "Missing Windows ansible_user ${ANSIBLE_SERVICE_USER}"; failed=1; }
    grep -q '^ansible_password[[:space:]]*=[[:space:]]*Password1' "$inventory_file" && pass "Found Windows lab password setting" || { fail "Missing Windows ansible_password"; failed=1; }
    grep -q '^ansible_connection[[:space:]]*=[[:space:]]*winrm' "$inventory_file" && pass "Found Windows WinRM connection setting" || { fail "Missing ansible_connection winrm"; failed=1; }
    grep -q "^ansible_port[[:space:]]*=[[:space:]]*${WINRM_PORT}" "$inventory_file" && pass "Found WinRM port ${WINRM_PORT}" || { fail "Missing ansible_port ${WINRM_PORT}"; failed=1; }
    grep -q "^ansible_winrm_transport[[:space:]]*=[[:space:]]*${WINRM_TRANSPORT}" "$inventory_file" && pass "Found WinRM transport ${WINRM_TRANSPORT}" || { fail "Missing ansible_winrm_transport ${WINRM_TRANSPORT}"; failed=1; }
    grep -q '^ansible_winrm_server_cert_validation[[:space:]]*=[[:space:]]*ignore' "$inventory_file" && pass "Found WinRM certificate validation setting" || { fail "Missing ansible_winrm_server_cert_validation ignore"; failed=1; }

    if (( failed == 0 )); then
        pass "Lab 5 inventory validation passed"
        return 0
    else
        fail "Lab 5 inventory validation failed"
        info "Run this to converge inventory from config/lab5.conf:"
        info "./scripts/lab5-act1-check.sh --apply-inventory"
        return 1
    fi
}
