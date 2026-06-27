#!/usr/bin/env bash
# ==============================================================================
# packages.sh
# ==============================================================================
#
# Shared package and Python dependency helpers for NSSA320 Lab 5.
#
# Purpose:
#  - Check required control node commands for Lab 5
#  - Detect the Python interpreter used by Ansible
#  - Install pip for the Ansible Python interpreter when needed
#  - Install Python WinRM dependencies needed for Ansible Windows management
#  - Verify that Ansible's Python can import winrm, requests, and requests_ntlm
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
# Version: 5.1
# Date: 2026-06-27
#
# Changes:
#  - Added Ansible Python interpreter detection.
#  - Updated Python module checks to use the same Python interpreter Ansible uses.
#  - Added pip package detection for Ansible's Python.
#  - Added idempotent helper to install python3.12-pip when Ansible uses Python 3.12.
#  - Fixed dependency workflow so pywinrm installs into the correct Python environment.
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
# Ansible Python Detection
# ==============================================================================

get_ansible_python_interpreter() {
    local python_path

    python_path="$(ansible --version 2>/dev/null | awk -F'[()]' '/python version/ {print $2}' | awk '{print $1}')"

    if [[ -z "$python_path" ]]; then
        fail "Could not detect Ansible Python interpreter from ansible --version"
        return 1
    fi

    if [[ ! -x "$python_path" ]]; then
        fail "Detected Ansible Python is not executable: ${python_path}"
        return 1
    fi

    printf '%s\n' "$python_path"
}

show_ansible_python_context() {
    local ansible_python

    step "Showing Ansible Python context"

    ansible --version || {
        fail "Unable to run ansible --version"
        return 1
    }

    ansible_python="$(get_ansible_python_interpreter)" || return 1

    info "Ansible Python interpreter: ${ansible_python}"

    "$ansible_python" --version || {
        fail "Unable to run detected Ansible Python: ${ansible_python}"
        return 1
    }

    return 0
}


# ==============================================================================
# Command Checks
# ==============================================================================

check_lab5_required_commands() {
    local failed=0

    step "Checking Lab 5 required commands"

    require_command ansible || failed=1
    require_command ansible-inventory || failed=1
    require_command dnf || failed=1

    if get_ansible_python_interpreter >/dev/null 2>&1; then
        pass "Ansible Python interpreter detected"
    else
        fail "Could not detect Ansible Python interpreter"
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

get_pip_package_for_ansible_python() {
    local ansible_python="$1"

    case "$ansible_python" in
        /usr/bin/python3.12)
            printf '%s\n' "python3.12-pip"
            ;;
        /usr/bin/python3)
            printf '%s\n' "python3-pip"
            ;;
        *)
            warn "No known RPM pip package mapping for ${ansible_python}"
            return 1
            ;;
    esac
}

check_ansible_python_pip() {
    local ansible_python

    step "Checking pip for Ansible Python"

    ansible_python="$(get_ansible_python_interpreter)" || return 1

    info "Ansible Python: ${ansible_python}"

    if "$ansible_python" -m pip --version >/dev/null 2>&1; then
        "$ansible_python" -m pip --version
        pass "pip is available for Ansible Python"
        return 0
    else
        warn "pip is missing for Ansible Python: ${ansible_python}"
        return 1
    fi
}

install_ansible_python_pip_if_missing() {
    local ansible_python
    local pip_package

    step "Ensuring pip is installed for Ansible Python"

    ansible_python="$(get_ansible_python_interpreter)" || return 1

    if "$ansible_python" -m pip --version >/dev/null 2>&1; then
        "$ansible_python" -m pip --version
        pass "pip already available for Ansible Python"
        return 0
    fi

    pip_package="$(get_pip_package_for_ansible_python "$ansible_python")" || {
        fail "Cannot determine pip RPM package for ${ansible_python}"
        return 1
    }

    info "Ansible Python is missing pip"
    info "Required RPM package: ${pip_package}"

    install_rpm_package_if_missing "$pip_package"

    if "$ansible_python" -m pip --version >/dev/null 2>&1; then
        "$ansible_python" -m pip --version
        pass "pip is now available for Ansible Python"
        return 0
    else
        fail "pip is still missing for Ansible Python after installing ${pip_package}"
        return 1
    fi
}


# ==============================================================================
# Python WinRM Dependency Helpers
# ==============================================================================

check_python_module_with_ansible_python() {
    local module_name="$1"
    local ansible_python

    step "Checking Python module with Ansible Python: ${module_name}"

    ansible_python="$(get_ansible_python_interpreter)" || return 1

    info "Using Python: ${ansible_python}"

    if "$ansible_python" -c "import ${module_name}" >/dev/null 2>&1; then
        pass "Python module is available to Ansible Python: ${module_name}"
        return 0
    else
        warn "Python module is missing from Ansible Python: ${module_name}"
        return 1
    fi
}

check_lab5_python_winrm_modules() {
    local failed=0

    step "Checking Lab 5 Python WinRM modules for Ansible Python"

    check_python_module_with_ansible_python winrm || failed=1
    check_python_module_with_ansible_python requests || failed=1
    check_python_module_with_ansible_python requests_ntlm || failed=1

    if (( failed == 0 )); then
        pass "All Lab 5 Python WinRM modules are available to Ansible Python"
        return 0
    else
        warn "One or more Lab 5 Python WinRM modules are missing from Ansible Python"
        return 1
    fi
}

install_lab5_python_winrm_modules_for_user() {
    local ansible_python

    step "Installing Lab 5 Python WinRM modules for current user"

    require_not_root

    ansible_python="$(get_ansible_python_interpreter)" || return 1

    info "Current user: $(whoami)"
    info "Using Ansible Python: ${ansible_python}"
    info "Installing: pywinrm requests requests-ntlm"

    "$ansible_python" -m pip install --user pywinrm requests requests-ntlm \
        || die "Failed to install Lab 5 Python WinRM modules for Ansible Python"

    pass "Lab 5 Python WinRM modules installed for current user"
}

show_lab5_python_dependency_versions() {
    local ansible_python

    step "Showing Lab 5 Python dependency versions"

    ansible_python="$(get_ansible_python_interpreter)" || return 1

    info "Ansible Python:"
    "$ansible_python" --version || warn "Unable to show Ansible Python version"

    info "pip:"
    if "$ansible_python" -m pip --version >/dev/null 2>&1; then
        "$ansible_python" -m pip --version
    else
        warn "pip is not available for Ansible Python"
    fi

    info "Python package details:"
    "$ansible_python" -m pip show pywinrm requests requests-ntlm 2>/dev/null \
        || warn "One or more Python packages are not visible to Ansible Python pip"
}


# ==============================================================================
# Full Package Workflows
# ==============================================================================

check_lab5_package_readiness() {
    local failed=0

    step "Checking Lab 5 package readiness"

    show_ansible_python_context || failed=1
    check_lab5_required_commands || failed=1
    check_ansible_python_pip || failed=1
    check_lab5_python_winrm_modules || failed=1
    show_lab5_python_dependency_versions || failed=1

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

    if ! check_ansible_python_pip; then
        fail "pip is missing for Ansible Python."
        info "Run this first, using sudo:"
        info "sudo dnf install -y python3.12-pip"
        return 1
    fi

    if check_lab5_python_winrm_modules; then
        pass "Lab 5 Python WinRM modules are already installed"
    else
        install_lab5_python_winrm_modules_for_user
    fi

    check_lab5_python_winrm_modules
    show_lab5_python_dependency_versions
}
