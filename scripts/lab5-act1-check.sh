#!/usr/bin/env bash
# ==============================================================================
# lab5-act1-check.sh
# ==============================================================================
#
# Activity 1 readiness and apply helper for NSSA320 Lab 5.
#
# Purpose:
#  - Check the Lab 5 control node environment
#  - Confirm Lab 5 host resolution and reachability
#  - Check Linux Ansible connectivity from the control node
#  - Check Windows 11 readiness for WinRM/Ansible management
#  - Intentionally apply Lab 5 /etc/hosts desired state when requested
#  - Intentionally apply Lab 5 inventory desired state when requested
#  - Print the required Figure 1 command sequence when ready
#
# Design:
#  - Default check modes do not change system state.
#  - Apply modes are explicit and intentional.
#  - /etc/hosts and inventory.inv are generated from config/lab5.conf.
#  - This keeps Lab 5 idempotent and avoids manual configuration drift.
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
#  - Added --apply-hosts mode to idempotently write the Lab 5 /etc/hosts block.
#  - Added --apply-inventory mode to idempotently write inventory.inv.
#  - Added inventory validation to quick, full, and Windows-only checks.
#  - Added lib/inventory.sh source.
#  - Kept normal check modes read-only.
#
# Version: 5.0
# Date: 2026-06-26
#
# Changes:
#  - Added first Lab 5 Activity 1 readiness runner.
#  - Added host plan display, resolution checks, ping checks, inventory checks,
#    Linux Ansible checks, Windows remote-port checks, and win_ping testing.
#
# Notes:
#  - If win_ping fails, this script reports what to check next.
#  - Required Lab 5 Figure 1 should still be captured manually using:
#      cd ~/lab5
#      date
#      ansible win11 -m win_ping
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

source "${BASE_DIR}/config/lab5.conf"
source "${BASE_DIR}/lib/common.sh"
source "${BASE_DIR}/lib/hosts.sh"
source "${BASE_DIR}/lib/checks.sh"
source "${BASE_DIR}/lib/inventory.sh"


# ==============================================================================
# Usage
# ==============================================================================

usage() {
    cat <<EOF
Usage:
  $0 [mode]

Modes:
  --quick             Run core reachability and Windows readiness checks
  --full              Run all checks including Linux Ansible connectivity
  --win-only          Check only Windows 11 readiness and win_ping
  --apply-hosts       Idempotently write the Lab 5 /etc/hosts managed block
  --apply-inventory   Idempotently write inventory.inv from config/lab5.conf
  --help              Show this help message

Examples:
  ./scripts/lab5-act1-check.sh --quick
  ./scripts/lab5-act1-check.sh --full
  ./scripts/lab5-act1-check.sh --win-only
  sudo ./scripts/lab5-act1-check.sh --apply-hosts
  ./scripts/lab5-act1-check.sh --apply-inventory

Description:
  Checks Lab 5 Activity 1 readiness from the control node.

  Normal check modes do not configure Windows or Linux. They only check current
  state and tell you what is ready or what needs attention.

  Apply modes are intentional and idempotent. They converge local project files
  or /etc/hosts to the desired state defined in config/lab5.conf.
EOF
}


# ==============================================================================
# Check Modes
# ==============================================================================

run_quick_checks() {
    local failed=0

    step "Starting Lab 5 quick readiness checks"

    require_not_root

    check_required_lab5_commands || failed=1
    show_control_node_context
    show_lab5_host_plan

    check_ansible_project_files || failed=1
    validate_lab5_inventory_file "./inventory.inv" || failed=1

    check_all_host_resolution || failed=1
    check_all_ping_targets || failed=1
    check_windows_readiness "$WIN11_HOST" || failed=1
    check_ansible_win_ping "$WIN11_HOST" || failed=1

    print_figure1_next_steps

    step "Lab 5 quick readiness summary"

    if (( failed == 0 )); then
        pass "Lab 5 quick readiness checks passed"
        return 0
    else
        warn "Lab 5 quick readiness checks found issues"
        return 1
    fi
}

run_full_checks() {
    local failed=0

    step "Starting Lab 5 full readiness checks"

    require_not_root

    check_required_lab5_commands || failed=1
    show_control_node_context
    show_lab5_host_plan

    check_ansible_project_files || failed=1
    validate_lab5_inventory_file "./inventory.inv" || failed=1

    check_all_host_resolution || failed=1
    check_all_ping_targets || failed=1
    check_ansible_inventory_graph || failed=1
    check_ansible_linux_ping || failed=1
    check_windows_readiness "$WIN11_HOST" || failed=1
    check_ansible_win_ping "$WIN11_HOST" || failed=1

    print_figure1_next_steps

    step "Lab 5 full readiness summary"

    if (( failed == 0 )); then
        pass "Lab 5 full readiness checks passed"
        return 0
    else
        warn "Lab 5 full readiness checks found issues"
        return 1
    fi
}

run_windows_only_checks() {
    local failed=0

    step "Starting Lab 5 Windows-only readiness checks"

    require_not_root

    check_required_lab5_commands || failed=1
    show_control_node_context
    show_lab5_host_plan

    check_ansible_project_files || failed=1
    validate_lab5_inventory_file "./inventory.inv" || failed=1

    check_host_resolution "$WIN11_HOST" || failed=1
    wait_for_host_ping "$WIN11_HOST" 5 12 || failed=1
    check_windows_remote_ports "$WIN11_HOST" || failed=1
    check_ansible_win_ping "$WIN11_HOST" || failed=1

    print_figure1_next_steps

    step "Lab 5 Windows-only readiness summary"

    if (( failed == 0 )); then
        pass "Lab 5 Windows-only readiness checks passed"
        return 0
    else
        warn "Lab 5 Windows-only readiness checks found issues"
        return 1
    fi
}


# ==============================================================================
# Apply Modes
# ==============================================================================

run_apply_hosts() {
    step "Applying Lab 5 hosts file configuration"

    require_root

    show_lab5_host_plan
    write_lab5_hosts_block
    show_lab5_hosts_block
    validate_hosts_resolution
}

run_apply_inventory() {
    step "Applying Lab 5 inventory configuration"

    require_not_root

    write_lab5_inventory_file "./inventory.inv"
    validate_lab5_inventory_file "./inventory.inv"
    check_ansible_inventory_graph
}


# ==============================================================================
# Main
# ==============================================================================

main() {
    local mode="${1:---quick}"

    cd "$BASE_DIR" || exit 1

    case "$mode" in
        --quick)
            run_quick_checks
            ;;
        --full)
            run_full_checks
            ;;
        --win-only)
            run_windows_only_checks
            ;;
        --apply-hosts)
            run_apply_hosts
            ;;
        --apply-inventory)
            run_apply_inventory
            ;;
        --help|-h)
            usage
            ;;
        *)
            fail "Invalid mode: ${mode}"
            usage
            exit 2
            ;;
    esac
}

main "$@"
