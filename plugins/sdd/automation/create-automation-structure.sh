#!/bin/bash
set -euo pipefail

# Directory Scaffolding Script for SDD Automation Framework
# Task: ASDW-1.1001 - Directory Scaffolding Script
# Purpose: Create foundational directory structure for automation framework

# Constants
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly EXIT_SUCCESS=0
readonly EXIT_INIT_ERROR=4

# Logging functions
log_info() {
    echo "[INFO] ${SCRIPT_NAME}: $*" >&2
}

log_warn() {
    echo "[WARN] ${SCRIPT_NAME}: $*" >&2
}

log_error() {
    echo "[ERROR] ${SCRIPT_NAME}: $*" >&2
}

# Cleanup on error
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Script failed with exit code ${exit_code}"
    fi
}

trap cleanup EXIT

# Validate environment
validate_environment() {
    log_info "Validating environment"

    if [[ -z "${SDD_ROOT_DIR:-}" ]]; then
        log_error "SDD_ROOT_DIR environment variable is not set"
        exit ${EXIT_INIT_ERROR}
    fi

    if [[ ! -d "${SDD_ROOT_DIR}" ]]; then
        log_error "SDD_ROOT_DIR does not exist: ${SDD_ROOT_DIR}"
        exit ${EXIT_INIT_ERROR}
    fi

    if [[ ! -w "${SDD_ROOT_DIR}" ]]; then
        log_error "SDD_ROOT_DIR is not writable: ${SDD_ROOT_DIR}"
        exit ${EXIT_INIT_ERROR}
    fi

    log_info "Environment validation passed: SDD_ROOT_DIR=${SDD_ROOT_DIR}"
}

# Create directory with specified permissions
create_directory() {
    local dir_path="$1"
    local permissions="$2"
    local dir_name
    dir_name="$(basename "${dir_path}")"

    if [[ -d "${dir_path}" ]]; then
        log_info "Directory already exists: ${dir_name}"

        # Check for existing content
        if [[ -n "$(ls -A "${dir_path}" 2>/dev/null)" ]]; then
            log_warn "Directory contains existing content: ${dir_name} (preserving)"
        fi

        # Update permissions if different
        local current_perms
        current_perms=$(stat -c '%a' "${dir_path}")
        if [[ "${current_perms}" != "${permissions}" ]]; then
            log_info "Updating permissions for ${dir_name}: ${current_perms} -> ${permissions}"
            chmod "${permissions}" "${dir_path}"
        fi
    else
        log_info "Creating directory: ${dir_name} (permissions: ${permissions})"
        mkdir -p "${dir_path}"
        chmod "${permissions}" "${dir_path}"
    fi
}

# Create automation directory structure
create_structure() {
    log_info "Creating automation directory structure"

    local automation_root="${SDD_ROOT_DIR}/automation"

    # Create main automation directory
    create_directory "${automation_root}" "755"

    # Create primary subdirectories
    create_directory "${automation_root}/lib" "755"
    create_directory "${automation_root}/modules" "755"
    create_directory "${automation_root}/config" "755"
    create_directory "${automation_root}/tests" "755"
    create_directory "${automation_root}/runs" "700"  # Sensitive runtime data

    # Create test fixture subdirectories
    create_directory "${automation_root}/tests/fixtures" "755"
    create_directory "${automation_root}/tests/fixtures/configs" "755"
    create_directory "${automation_root}/tests/fixtures/modules" "755"
    create_directory "${automation_root}/tests/fixtures/states" "755"

    log_info "Directory structure creation completed"
}

# Verify final structure
verify_structure() {
    log_info "Verifying directory structure"

    local automation_root="${SDD_ROOT_DIR}/automation"
    local all_verified=true

    # Define expected directories with permissions
    declare -A expected_dirs=(
        ["${automation_root}"]="755"
        ["${automation_root}/lib"]="755"
        ["${automation_root}/modules"]="755"
        ["${automation_root}/config"]="755"
        ["${automation_root}/tests"]="755"
        ["${automation_root}/tests/fixtures"]="755"
        ["${automation_root}/tests/fixtures/configs"]="755"
        ["${automation_root}/tests/fixtures/modules"]="755"
        ["${automation_root}/tests/fixtures/states"]="755"
        ["${automation_root}/runs"]="700"
    )

    for dir in "${!expected_dirs[@]}"; do
        local expected_perm="${expected_dirs[$dir]}"

        if [[ ! -d "${dir}" ]]; then
            log_error "Verification failed: directory does not exist: ${dir}"
            all_verified=false
            continue
        fi

        local actual_perm
        actual_perm=$(stat -c '%a' "${dir}")
        if [[ "${actual_perm}" != "${expected_perm}" ]]; then
            log_error "Verification failed: incorrect permissions for ${dir}: expected ${expected_perm}, got ${actual_perm}"
            all_verified=false
        fi
    done

    if [[ "${all_verified}" == "true" ]]; then
        log_info "Structure verification passed - all directories present with correct permissions"
        return 0
    else
        log_error "Structure verification failed - see errors above"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting automation directory scaffolding"

    validate_environment
    create_structure

    if verify_structure; then
        log_info "Automation directory scaffolding completed successfully"
        exit ${EXIT_SUCCESS}
    else
        log_error "Automation directory scaffolding completed with errors"
        exit ${EXIT_INIT_ERROR}
    fi
}

# Run main function
main "$@"
