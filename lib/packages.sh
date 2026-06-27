#!/usr/bin/env bash
# ==============================================================================
# packages.sh
# ==============================================================================
#
# Shared package and Python dependency helpers for NSSA320 Lab 5.
#
# Purpose:
#  - Check required control node commands for Lab 5
#  - Install OS packages needed for Python package management
#  - Install Python WinRM dependencies needed for Ansible Windows management
#  - Verify that the control node can import winrm, requests, and requests_ntlm
#
# Design:
#  - This file does not auto-run actions when sourced.
#  - Check functions do not change system state.
#  - Apply functions intentionally install missing dependencies.
#  - Python WinRM packages are installed for the normal student user because
#    Ansible is normally run as student, not root.
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
#  - Added Lab 5 package helper library.
#  - Added checks for Ansible, Python 3, pip, and WinRM Python modules.
#  - Added python3-pip installation helper.
#  - Added user-level pip install helper for pywinrm, requests, and requests-ntlm.
#
# ==============================================================================


# ==============================================================================
# Source Guard
# ==============================================================================

if [[ -n "${LAB5_PACKAGES_SH_LOADED:-}" ]]; then
    return 0
fi

LAB5_PACKAGES_SH_LOADED="true"


# ==============================================================================
# Command Checks
# ==============================================================================

check_lab5_required_commands() {
    local failed=0

    step "Checking Lab 5 required commands"

    require_command ansible || failed=1
    require_command ansible-inventory || failed=1
    require_command python3 || failed=1
    require_command dnf || failed=1

    if command -v pip3 >/dev/null 2>&1; then
        pass "Required command found: pip3"
    elif python3 -m pip --version >/dev/null 2>&1; then
        pass "Python pip module is available"
    else
        warn "pip is not available yet"
        failed=1
    fi

    if (( failed == 0 )); then
        pass "All required Lab 5 commands are available"
        return 0
    else
        warn "One or more required Lab 5 commands are missing"
        return 1
    fi
}


# ==============================================================================
# OS Package Helpers
# ==============================================================================

check_rpm_package_installed() {
    local package_name="$1"

    step "Checking RPM package: ${package_name}"

    if rpm -q "$package_name" >/dev/null 2>&1; then
        pass "Package is installed: ${package_name}"
        return 0
    else
        warn "Package is not installed: ${package_name}"
        return 1
    fi
}

install_rpm_package_if_missing() {
    local package_name="$1"

    step "Ensuring RPM package is installed: ${package_name}"

    if rpm -q "$package_name" >/dev/null 2>&1; then
        pass "Package already installed: ${package_name}"
        return 0
    fi

    require_root

    info "Installing package: ${package_name}"
    dnf install -y "$package_name" || die "Failed to install package: ${package_name}"

    pass "Package installation completed: ${package_name}"
}

install_lab5_os_packages() {
    step "Installing Lab 5 OS packages"

    install_rpm_package_if_missing python3-pip
}


# ==============================================================================
# Python WinRM Dependency Helpers
# ==============================================================================

check_python_module() {
    local module_name="$1"

    step "Checking Python module: ${module_name}"

    if python3 -c "import ${module_name}" >/dev/null 2>&1; then
        pass "Python module is available: ${module_name}"
        return 0
    else
        warn "Python module is missing: ${module_name}"
        return 1
    fi
}

check_lab5_python_winrm_modules() {
    local failed=0

    step "Checking Lab 5 Python WinRM modules"

    check_python_module winrm || failed=1
    check_python_module requests || failed=1
    check_python_module requests_ntlm || failed=1

    if (( failed == 0 )); then
        pass "All Lab 5 Python WinRM modules are available"
        return 0
    else
        warn "One or more Lab 5 Python WinRM modules are missing"
        return 1
    fi
}

install_lab5_python_winrm_modules_for_user() {
    step "Installing Lab 5 Python WinRM modules for current user"

    require_not_root

    info "Current user: $(whoami)"
    info "Installing: pywinrm requests requests-ntlm"

    python3 -m pip install --user pywinrm requests requests-ntlm \
        || die "Failed to install Lab 5 Python WinRM modules"

    pass "Lab 5 Python WinRM modules installed for current user"
}

show_lab5_python_dependency_versions() {
    step "Showing Lab 5 Python dependency versions"

    python3 --version || warn "Unable to show Python version"

    if python3 -m pip --version >/dev/null 2>&1; then
        python3 -m pip --version
    else
        warn "pip is not available"
    fi

    python3 -m pip show pywinrm requests requests-ntlm 2>/dev/null \
        || warn "One or more Python packages are not visible to pip show"
}


# ==============================================================================
# Full Package Workflows
# ==============================================================================

check_lab5_package_readiness() {
    local failed=0

    step "Checking Lab 5 package readiness"

    check_lab5_required_commands || failed=1
    check_lab5_python_winrm_modules || failed=1
    show_lab5_python_dependency_versions

    if (( failed == 0 )); then
        pass "Lab 5 package readiness checks passed"
        return 0
    else
        warn "Lab 5 package readiness checks found issues"
        return 1
    fi
}

apply_lab5_python_dependencies() {
    step "Applying Lab 5 Python dependency setup"

    require_not_root

    if ! python3 -m pip --version >/dev/null 2>&1; then
        fail "pip is not available for python3."
        info "Run this first:"
        info "sudo dnf install -y python3-pip"
        return 1
    fi

    install_lab5_python_winrm_modules_for_user
    check_lab5_python_winrm_modules
    show_lab5_python_dependency_versions
}
