#!/usr/bin/env bash
# ==============================================================================
# hosts.sh
# ==============================================================================
#
# Shared hostname and /etc/hosts helpers for NSSA320 Lab 5.
#
# Purpose:
#  - Map Lab 5 host names to the correct FQDN and IP address
#  - Display the expected Lab 5 host plan
#  - Manage the Lab 5 /etc/hosts block idempotently when needed
#  - Validate short-name resolution from the control node
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Functions are called by Lab 5 scripts such as lab5-act1-check.sh.
#  - Host data is read from config/lab5.conf.
#  - Output is handled through lib/common.sh.
#
# RICE Framework:
#  - Reproducibility: Hostname and /etc/hosts values come from one config file.
#  - Idempotency: Existing managed /etc/hosts block is replaced, not duplicated.
#  - Composability: Control node scripts can reuse the same host functions.
#  - Evolvability: New hosts can be added later by updating config and mapping.
#
# Dependencies:
#  - config/lab5.conf must be sourced before this file is used.
#  - lib/common.sh must be sourced before this file is used.
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
#  - Reused the Lab 4 hosts helper style as the Lab 5 baseline.
#  - Added Windows 11 host mapping for win11.
#  - Updated the managed /etc/hosts block for Lab 5.
#  - Removed hostname-changing helpers to keep Lab 5 Activity 1 focused on checks.
#
# Notes:
#  - This library supports Lab 5 host planning and validation.
#  - It does not configure Windows WinRM by itself.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================
#
# Purpose:
#  - Prevent this file from being loaded more than once in the same shell session.
# ==============================================================================

if [[ -n "${LAB5_HOSTS_SH_LOADED:-}" ]]; then
    return 0
fi

LAB5_HOSTS_SH_LOADED="true"


# ==============================================================================
# Host Mapping Helpers
# ==============================================================================

get_host_short() {
    local host="$1"

    case "$host" in
        control)
            printf '%s\n' "$CONTROL_HOST"
            ;;
        ansible1)
            printf '%s\n' "$ANSIBLE1_HOST"
            ;;
        ansible2)
            printf '%s\n' "$ANSIBLE2_HOST"
            ;;
        ubuntu)
            printf '%s\n' "$UBUNTU_HOST"
            ;;
        win11)
            printf '%s\n' "$WIN11_HOST"
            ;;
        gateway)
            printf '%s\n' "$GATEWAY_HOST"
            ;;
        *)
            die "Unknown host '${host}'. Valid hosts: gateway, control, ansible1, ansible2, ubuntu, win11"
            ;;
    esac
}

get_host_ip() {
    local host="$1"

    case "$host" in
        control)
            printf '%s\n' "$CONTROL_IP"
            ;;
        ansible1)
            printf '%s\n' "$ANSIBLE1_IP"
            ;;
        ansible2)
            printf '%s\n' "$ANSIBLE2_IP"
            ;;
        ubuntu)
            printf '%s\n' "$UBUNTU_IP"
            ;;
        win11)
            printf '%s\n' "$WIN11_IP"
            ;;
        gateway)
            printf '%s\n' "$GATEWAY_IP"
            ;;
        *)
            die "Unknown host '${host}'. Valid hosts: gateway, control, ansible1, ansible2, ubuntu, win11"
            ;;
    esac
}

get_host_fqdn() {
    local host="$1"
    local short_name

    short_name="$(get_host_short "$host")"
    printf '%s.%s\n' "$short_name" "$DOMAIN"
}


# ==============================================================================
# Host Plan Display
# ==============================================================================

show_lab5_host_plan() {
    local host
    local ip
    local fqdn
    local short_name

    step "Displaying Lab 5 host plan"

    for host in $PING_TARGETS; do
        short_name="$(get_host_short "$host")"
        ip="$(get_host_ip "$host")"
        fqdn="$(get_host_fqdn "$host")"

        info "${ip}  ${fqdn}  ${short_name}"
    done
}


# ==============================================================================
# /etc/hosts Management
# ==============================================================================

backup_hosts_file() {
    local backup_file

    backup_file="/etc/hosts.bak.$(date +%Y%m%d-%H%M%S)"

    info "Backing up /etc/hosts to ${backup_file}"
    cp /etc/hosts "$backup_file" || die "Failed to back up /etc/hosts"

    pass "Backup created: ${backup_file}"
}

write_lab5_hosts_block() {
    step "Writing Lab 5 managed block to /etc/hosts"

    require_root
    backup_hosts_file

    info "Removing existing Lab 5 managed block if present"

    sed -i '/# BEGIN NSSA320 LAB5 HOSTS/,/# END NSSA320 LAB5 HOSTS/d' /etc/hosts \
        || die "Failed to remove existing Lab 5 hosts block"

    info "Appending refreshed Lab 5 hosts block"

    cat >> /etc/hosts <<EOF

# BEGIN NSSA320 LAB5 HOSTS
# Managed by Lab 5 control node scripts.
# Do not manually edit inside this block unless you also update config/lab5.conf.
${CONTROL_IP}  ${CONTROL_FQDN}   ${CONTROL_HOST}
${ANSIBLE1_IP} ${ANSIBLE1_FQDN}  ${ANSIBLE1_HOST}
${ANSIBLE2_IP} ${ANSIBLE2_FQDN}  ${ANSIBLE2_HOST}
${UBUNTU_IP}   ${UBUNTU_FQDN}    ${UBUNTU_HOST}
${WIN11_IP}    ${WIN11_FQDN}     ${WIN11_HOST}
${GATEWAY_IP}  ${GATEWAY_FQDN}   ${GATEWAY_HOST}
# END NSSA320 LAB5 HOSTS
EOF

    pass "Lab 5 /etc/hosts block written"
}

show_lab5_hosts_block() {
    step "Displaying Lab 5 /etc/hosts managed block"

    if grep -q '# BEGIN NSSA320 LAB5 HOSTS' /etc/hosts; then
        sed -n '/# BEGIN NSSA320 LAB5 HOSTS/,/# END NSSA320 LAB5 HOSTS/p' /etc/hosts
        return 0
    else
        warn "Lab 5 managed hosts block was not found in /etc/hosts"
        return 1
    fi
}

validate_hosts_resolution() {
    local failed=0
    local host
    local expected_ip
    local resolved_line

    step "Validating local host resolution"

    for host in $PING_TARGETS; do
        expected_ip="$(get_host_ip "$host")"

        info "Resolving ${host}"

        if getent hosts "$host" >/dev/null 2>&1; then
            resolved_line="$(getent hosts "$host" | head -n 1)"
            pass "Resolved ${host}: ${resolved_line}"

            if printf '%s\n' "$resolved_line" | grep -q "^${expected_ip}[[:space:]]"; then
                pass "${host} resolves to expected IP: ${expected_ip}"
            else
                warn "${host} resolved, but not to expected IP ${expected_ip}"
            fi
        else
            fail "Could not resolve ${host}"
            failed=1
        fi
    done

    if (( failed == 0 )); then
        pass "All Lab 5 short hostnames resolved successfully"
        return 0
    else
        fail "One or more Lab 5 hostnames failed to resolve"
        return 1
    fi
}
