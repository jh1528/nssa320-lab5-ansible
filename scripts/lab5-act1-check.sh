#!/usr/bin/env bash
# ==============================================================================
# lab5-act1-check.sh
# ==============================================================================
#
# Activity 1 readiness check script for NSSA320 Lab 5.
#
# Purpose:
#  - Check the Lab 5 control node environment
#  - Confirm Lab 5 host resolution and reachability
#  - Check Linux Ansible connectivity from the control node
#  - Check Windows 11 readiness for WinRM/Ansible management
#  - Print the required Figure 1 command sequence when ready
#
# Design:
#  - This is a check/validation script, not a configuration script.
#  - It is safe to re-run because it does not change system state.
#  - It sources shared config and helper libraries.
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


# ==============================================================================
# Usage
# ==============================================================================

usage() {
    cat <<EOF
Usage:
  $0 [mode]

Modes:
  --quick       Run core reachability and Windows readiness checks
  --full        Run all checks including Linux Ansible connectivity
  --win-only    Check only Windows 11 readiness and win_ping
  --help        Show this help message

Examples:
  ./scripts/lab5-act1-check.sh --quick
  ./scripts/lab5-act1-check.sh --full
  ./scripts/lab5-act1-check.sh --win-only

Description:
  Checks Lab 5 Activity 1 readiness from the control node.

  This script does not configure Windows or Linux. It only checks current state
  and tells you what is ready or what needs attention.
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
