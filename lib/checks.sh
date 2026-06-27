#!/usr/bin/env bash
# ==============================================================================
# checks.sh
# ==============================================================================
#
# Shared readiness-check helpers for NSSA320 Lab 5.
#
# Purpose:
#  - Check Lab 5 host reachability from the control node
#  - Validate hostname resolution using the Lab 5 host plan
#  - Check important remote-management ports such as SSH and WinRM
#  - Check Ansible inventory visibility
#  - Test Windows Ansible connectivity with win_ping when available
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Functions are called by scripts such as lab5-act1-check.sh.
#  - Checks are safe to re-run and do not change system state.
#  - Host data is read from config/lab5.conf and lib/hosts.sh.
#  - Output is handled through lib/common.sh.
#
# RICE Framework:
#  - Reproducibility: Checks use the same config values every run.
#  - Idempotency: These checks observe/report state without changing it.
#  - Composability: Runner scripts can reuse these functions as needed.
#  - Evolvability: More Lab 5 checks can be added later without rewriting runners.
#
# Dependencies:
#  - config/lab5.conf must be sourced before this file is used.
#  - lib/common.sh must be sourced before this file is used.
#  - lib/hosts.sh must be sourced before this file is used.
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
#  - Added Lab 5 control node readiness checks.
#  - Added ping checks for expected lab hosts.
#  - Added TCP port checks for SSH and WinRM.
#  - Added Ansible inventory graph check.
#  - Added optional Windows win_ping check.
#
# Notes:
#  - This library does not configure Windows WinRM.
#  - If WinRM is not ready, the script reports the next action instead of changing Windows.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================

if [[ -n "${LAB5_CHECKS_SH_LOADED:-}" ]]; then
    return 0
fi

LAB5_CHECKS_SH_LOADED="true"


# ==============================================================================
# Basic Control Node Checks
# ==============================================================================

check_required_lab5_commands() {
    step "Checking required commands on the control node"

    require_command hostname
    require_command getent
    require_command ping
    require_command timeout
    require_command ansible
    require_command ansible-inventory

    if command -v nc >/dev/null 2>&1; then
        pass "Required command found: nc"
    elif command -v ncat >/dev/null 2>&1; then
        pass "Required command found: ncat"
    else
        warn "Neither nc nor ncat was found. TCP port checks will be skipped."
    fi
}

show_control_node_context() {
    step "Control node context"

    info "Current user: $(whoami)"
    info "Current hostname: $(hostname)"
    info "Current directory: $(pwd)"

    info "Current IPv4 addresses:"
    ip -4 -brief addr show 2>/dev/null || warn "Unable to show IPv4 addresses"

    info "Current default route:"
    ip route | grep '^default' 2>/dev/null || warn "No default route found"
}


# ==============================================================================
# Host Resolution Checks
# ==============================================================================

check_host_resolution() {
    local host="$1"
    local expected_ip
    local resolved_line

    expected_ip="$(get_host_ip "$host")"

    info "Resolving ${host}"

    if ! getent hosts "$host" >/dev/null 2>&1; then
        fail "Could not resolve ${host}"
        return 1
    fi

    resolved_line="$(getent hosts "$host" | head -n 1)"
    pass "Resolved ${host}: ${resolved_line}"

    if printf '%s\n' "$resolved_line" | grep -q "^${expected_ip}[[:space:]]"; then
        pass "${host} resolves to expected IP: ${expected_ip}"
        return 0
    else
        warn "${host} resolved, but not to expected IP ${expected_ip}"
        return 1
    fi
}

check_all_host_resolution() {
    local host
    local failed=0

    step "Checking Lab 5 hostname resolution"

    for host in $PING_TARGETS; do
        check_host_resolution "$host" || failed=1
    done

    if (( failed == 0 )); then
        pass "All Lab 5 hostnames resolved correctly"
        return 0
    else
        fail "One or more Lab 5 hostname checks failed"
        return 1
    fi
}


# ==============================================================================
# Ping Checks
# ==============================================================================

check_ping_by_ip() {
    local host="$1"
    local ip

    ip="$(get_host_ip "$host")"

    info "Pinging ${host} by IP: ${ip}"

    if ping -c 2 -W 2 "$ip" >/tmp/lab5_ping_"$host".out 2>&1; then
        cat /tmp/lab5_ping_"$host".out
        pass "${host} is reachable by IP: ${ip}"
        return 0
    else
        cat /tmp/lab5_ping_"$host".out
        fail "${host} is not reachable by IP: ${ip}"
        return 1
    fi
}

check_ping_by_name() {
    local host="$1"

    info "Pinging ${host} by hostname"

    if ping -c 2 -W 2 "$host" >/tmp/lab5_ping_name_"$host".out 2>&1; then
        cat /tmp/lab5_ping_name_"$host".out
        pass "${host} is reachable by hostname"
        return 0
    else
        cat /tmp/lab5_ping_name_"$host".out
        fail "${host} is not reachable by hostname"
        return 1
    fi
}

check_all_ping_targets() {
    local host
    local failed=0

    step "Checking Lab 5 host reachability by IP"

    for host in $PING_TARGETS; do
        check_ping_by_ip "$host" || failed=1
    done

    step "Checking Lab 5 host reachability by hostname"

    for host in $PING_TARGETS; do
        check_ping_by_name "$host" || failed=1
    done

    if (( failed == 0 )); then
        pass "All Lab 5 ping checks passed"
        return 0
    else
        fail "One or more Lab 5 ping checks failed"
        return 1
    fi
}

wait_for_host_ping() {
    local host="$1"
    local delay="${2:-5}"
    local max_attempts="${3:-12}"
    local attempt=1
    local ip

    ip="$(get_host_ip "$host")"

    step "Waiting for ${host} to respond to ping"

    info "Host: ${host}"
    info "IP: ${ip}"
    info "Delay between attempts: ${delay} seconds"
    info "Max attempts: ${max_attempts}"

    while (( attempt <= max_attempts )); do
        info "Attempt ${attempt}/${max_attempts}: ping ${ip}"

        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            pass "${host} is reachable by ping"
            return 0
        fi

        warn "${host} is not reachable yet"
        sleep "$delay"
        attempt=$(( attempt + 1 ))
    done

    fail "${host} did not respond to ping after ${max_attempts} attempts"
    return 1
}


# ==============================================================================
# TCP Port Checks
# ==============================================================================

_check_tcp_port_with_available_tool() {
    local host="$1"
    local port="$2"

    if command -v nc >/dev/null 2>&1; then
        nc -z -w 3 "$host" "$port" >/dev/null 2>&1
        return $?
    elif command -v ncat >/dev/null 2>&1; then
        ncat -z -w 3 "$host" "$port" >/dev/null 2>&1
        return $?
    else
        return 3
    fi
}

check_tcp_port() {
    local host="$1"
    local port="$2"
    local label="${3:-TCP port ${port}}"
    local result

    info "Checking ${label} on ${host}:${port}"

    _check_tcp_port_with_available_tool "$host" "$port"
    result=$?

    case "$result" in
        0)
            pass "${label} is open on ${host}:${port}"
            return 0
            ;;
        3)
            warn "Skipping ${label} check because nc/ncat is not installed"
            return 1
            ;;
        *)
            warn "${label} is not open on ${host}:${port}"
            return 1
            ;;
    esac
}

check_windows_remote_ports() {
    local host="${1:-$WIN11_HOST}"
    local failed=0

    step "Checking Windows remote access ports"

    check_tcp_port "$host" 22 "SSH" || failed=1
    check_tcp_port "$host" "$WINRM_PORT" "WinRM HTTP" || failed=1

    if (( failed == 0 )); then
        pass "Windows SSH and WinRM ports are reachable"
        return 0
    else
        warn "One or more Windows remote access ports are not reachable"
        return 1
    fi
}


# ==============================================================================
# Ansible Checks
# ==============================================================================

check_ansible_project_files() {
    step "Checking Lab 5 Ansible project files"

    require_file "./ansible.cfg"
    require_file "./inventory.inv"
}

check_ansible_inventory_graph() {
    step "Checking Ansible inventory graph"

    if ansible-inventory --graph; then
        pass "Ansible inventory graph displayed successfully"
        return 0
    else
        fail "Ansible inventory graph failed"
        return 1
    fi
}

check_ansible_linux_ping() {
    local failed=0

    step "Checking Ansible Linux connectivity"

    if ansible ubuntu -m ping; then
        pass "Ansible ping succeeded for ubuntu"
    else
        fail "Ansible ping failed for ubuntu"
        failed=1
    fi

    if ansible rocky_hosts -m ping; then
        pass "Ansible ping succeeded for rocky_hosts"
    else
        fail "Ansible ping failed for rocky_hosts"
        failed=1
    fi

    if (( failed == 0 )); then
        pass "Linux Ansible connectivity checks passed"
        return 0
    else
        fail "One or more Linux Ansible connectivity checks failed"
        return 1
    fi
}

check_ansible_win_ping() {
    local host="${1:-$WIN11_HOST}"

    step "Checking Windows Ansible connectivity with win_ping"

    info "Running: ansible ${host} -m win_ping"

    if ansible "$host" -m win_ping; then
        pass "${host} is ready for Ansible management through WinRM"
        return 0
    else
        warn "Ansible win_ping failed for ${host}"
        warn "If ping works but win_ping fails, check WinRM, inventory variables, credentials, and local Administrator rights."
        return 1
    fi
}


# ==============================================================================
# Windows Readiness Summary
# ==============================================================================

check_windows_readiness() {
    local host="${1:-$WIN11_HOST}"
    local failed=0

    step "Checking Windows 11 readiness for Lab 5"

    wait_for_host_ping "$host" 5 12 || failed=1

    check_host_resolution "$host" || failed=1

    check_tcp_port "$host" "$WINRM_PORT" "WinRM HTTP" || {
        warn "WinRM does not appear ready yet."
        warn "If SSH is available, the control node may be able to push the PowerShell bootstrap."
        warn "If SSH is not available, run the PowerShell bootstrap from the Windows console."
        failed=1
    }

    check_tcp_port "$host" 22 "SSH" || {
        warn "SSH does not appear open on Windows. This is okay if you plan to use WinRM only."
    }

    if (( failed == 0 )); then
        pass "Windows basic readiness checks passed"
        return 0
    else
        warn "Windows readiness checks found issues"
        return 1
    fi
}

print_figure1_next_steps() {
    step "Figure 1 next steps"

    info "When win_ping works, take the required screenshot with:"
    printf '\n'
    printf '  cd ~/lab5\n'
    printf '  date\n'
    printf '  ansible win11 -m win_ping\n'
    printf '\n'
    info "The screenshot must show the date command and successful win_ping output in the same terminal."
}
