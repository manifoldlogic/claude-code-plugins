#!/usr/bin/env bash
#
# common.sh - Shared logging and utility functions for SDD automation framework
#
# This library provides unified logging infrastructure with:
# - Four log levels: debug, info, warn, error
# - Dual output: console (respecting LOG_LEVEL) and file (all levels)
# - Security-conscious sanitization of tokens and credentials
# - ISO 8601 timestamps with timezone
# - Automatic component detection from caller context
#
# Usage:
#   source "${SDD_ROOT}/automation/lib/common.sh"
#   log_info "Starting process"
#   log_error "Failed to connect"
#
# Environment Variables:
#   CONFIG_LOG_LEVEL - Console log level (debug|info|warn|error), default: info
#   LOG_FILE - Log file path, default: /tmp/sdd-automation.log
#   COMPONENT - Component name for log entries, auto-detected if not set
#

set -euo pipefail

# Set default values for logging configuration
: "${CONFIG_LOG_LEVEL:=info}"
: "${LOG_FILE:=/tmp/sdd-automation.log}"

# Log level priority mapping for comparison
declare -A LOG_LEVEL_PRIORITY=(
    [debug]=0
    [info]=1
    [warn]=2
    [error]=3
)

#
# sanitize_log_message - Remove sensitive data from log messages
#
# Removes:
# - API tokens (sk-*, ghp_*, gho_*)
# - Passwords in key=value format
# - Authorization headers
#
# Arguments:
#   $1 - Message to sanitize
#
# Returns:
#   Sanitized message on stdout
#
sanitize_log_message() {
    local message="$1"

    # Sanitize API tokens (OpenAI, GitHub PAT, GitHub OAuth)
    message=$(echo "$message" | sed -E 's/(sk-|ghp_|gho_)[a-zA-Z0-9_-]+/[TOKEN_REDACTED]/g')

    # Sanitize passwords in key=value format
    message=$(echo "$message" | sed -E 's/password=[^ ]*/password=[REDACTED]/g')

    # Sanitize Authorization headers
    message=$(echo "$message" | sed -E 's/Authorization: [^ ]*/Authorization: [REDACTED]/g')

    echo "$message"
}

#
# get_component_name - Auto-detect component name from caller context
#
# Attempts to determine component name from:
# 1. COMPONENT environment variable (if set)
# 2. Calling script name (basename without extension)
# 3. Falls back to "unknown"
#
# Returns:
#   Component name on stdout
#
get_component_name() {
    # shellcheck disable=SC2153
    if [ -n "${COMPONENT:-}" ]; then
        echo "$COMPONENT"
    elif [ -n "${BASH_SOURCE[3]:-}" ]; then
        # Get the script name that called the log function
        # Call stack: [0]=get_component_name [1]=write_log [2]=log_* [3]=caller
        basename "${BASH_SOURCE[3]}" .sh
    else
        echo "unknown"
    fi
}

#
# should_log_to_console - Determine if message should be logged to console
#
# Arguments:
#   $1 - Log level (debug|info|warn|error)
#
# Returns:
#   0 if should log, 1 if should not log
#
should_log_to_console() {
    local level="$1"
    local configured_priority="${LOG_LEVEL_PRIORITY[$CONFIG_LOG_LEVEL]}"
    local message_priority="${LOG_LEVEL_PRIORITY[$level]}"

    # If configured level is not recognized, default to info
    if [ -z "$configured_priority" ]; then
        configured_priority=1
    fi

    # Log if message priority >= configured priority
    [ "$message_priority" -ge "$configured_priority" ]
}

#
# write_log - Internal function to write log entries
#
# Arguments:
#   $1 - Log level (DEBUG|INFO|WARN|ERROR)
#   $2 - Log message
#   $3 - Output stream (stdout|stderr)
#
write_log() {
    local level="$1"
    local message="$2"
    local stream="$3"
    local level_lower="${level,,}"

    # Sanitize the message
    local sanitized
    sanitized=$(sanitize_log_message "$message")

    # Get ISO 8601 timestamp with timezone
    local timestamp
    timestamp=$(date -Iseconds)

    # Get component name
    local component
    component=$(get_component_name)

    # Format: YYYY-MM-DDTHH:MM:SS|LEVEL|COMPONENT|MESSAGE
    local log_line="${timestamp}|${level}|${component}|${sanitized}"

    # Always write to file (all levels)
    if [ -n "$LOG_FILE" ]; then
        echo "$log_line" >> "$LOG_FILE" 2>/dev/null || true
    fi

    # Write to console if level is appropriate
    if should_log_to_console "$level_lower"; then
        if [ "$stream" = "stderr" ]; then
            echo "$log_line" >&2
        else
            echo "$log_line"
        fi
    fi
}

#
# log_debug - Log debug-level message
#
# Debug messages are for detailed diagnostic information useful during development
# and troubleshooting. Only shown on console when CONFIG_LOG_LEVEL=debug.
#
# Arguments:
#   $1 - Log message
#
log_debug() {
    write_log "DEBUG" "$1" "stdout"
}

#
# log_info - Log info-level message
#
# Info messages are for general informational messages about normal operations.
# Shown on console when CONFIG_LOG_LEVEL is debug or info.
#
# Arguments:
#   $1 - Log message
#
log_info() {
    write_log "INFO" "$1" "stdout"
}

#
# log_warn - Log warning-level message
#
# Warning messages indicate potentially problematic situations that don't prevent
# operation but may require attention. Shown on console when CONFIG_LOG_LEVEL is
# debug, info, or warn.
#
# Arguments:
#   $1 - Log message
#
log_warn() {
    write_log "WARN" "$1" "stdout"
}

#
# log_error - Log error-level message
#
# Error messages indicate serious problems that prevent normal operation.
# Always shown on console regardless of CONFIG_LOG_LEVEL. Written to stderr.
#
# Arguments:
#   $1 - Log message
#
log_error() {
    write_log "ERROR" "$1" "stderr"
}

#
# JSON Helper Functions
#
# These functions provide consistent JSON parsing and validation for module
# responses and configuration files. All modules in the SDD automation framework
# return JSON following the standard contract:
#
# {
#   "success": boolean,
#   "result": object,
#   "next_action": "proceed" | "retry" | "block" | "complete",
#   "error": string | null
# }
#
# Dependencies:
#   - jq (command-line JSON processor)
#

#
# is_success - Check if JSON response indicates success
#
# Examines the "success" field in a JSON response to determine if an operation
# succeeded. Handles missing fields gracefully by defaulting to false.
#
# Arguments:
#   $1 - JSON string to check
#
# Returns:
#   0 if success field is true, 1 otherwise
#
# Examples:
#   response='{"success": true, "result": {"key": "value"}}'
#   if is_success "$response"; then
#       echo "Operation succeeded"
#   fi
#
#   # Handles missing success field
#   response='{"result": {}}'
#   if is_success "$response"; then
#       echo "This won't print"  # success defaults to false
#   fi
#
#   # Handles malformed JSON gracefully
#   response='{broken json'
#   if is_success "$response"; then
#       echo "This won't print"  # Returns failure, no crash
#   fi
#
is_success() {
    local json="$1"
    local success
    success=$(echo "$json" | jq -r '.success // false' 2>/dev/null)
    [ "$success" = "true" ]
}

#
# extract_field - Extract a named field from JSON
#
# Extracts a field value from JSON using jq syntax. Supports nested field access
# using dot notation (e.g., "result.key"). Returns empty string if field doesn't
# exist or JSON is malformed.
#
# Arguments:
#   $1 - JSON string
#   $2 - Field path in jq syntax (e.g., "result", "result.key")
#
# Returns:
#   Field value on stdout (raw, unquoted), empty if field missing or invalid JSON
#   Exit code: 0 on success, 1 on error
#
# Examples:
#   response='{"success": true, "result": {"key": "value"}}'
#   result=$(extract_field "$response" "result")
#   echo "$result"  # {"key": "value"}
#
#   # Extract nested field
#   key=$(extract_field "$response" "result.key")
#   echo "$key"  # value
#
#   # Missing field returns empty
#   missing=$(extract_field "$response" "nonexistent")
#   echo "$missing"  # (empty string)
#
#   # Malformed JSON returns empty, no crash
#   value=$(extract_field '{broken' "field")
#   echo "$value"  # (empty string)
#
extract_field() {
    local json="$1"
    local field="$2"
    echo "$json" | jq -r ".$field // empty" 2>/dev/null
}

#
# validate_json - Validate that a string is well-formed JSON
#
# Uses jq to parse and validate JSON structure without producing output.
# Useful for checking configuration files or module responses before processing.
#
# Arguments:
#   $1 - String to validate
#
# Returns:
#   0 if JSON is valid, 1 if invalid or malformed
#
# Examples:
#   config='{"retry": {"max_attempts": 3}}'
#   if validate_json "$config"; then
#       attempts=$(extract_field "$config" "retry.max_attempts")
#       echo "Max attempts: $attempts"
#   fi
#
#   # Invalid JSON returns failure
#   if validate_json '{broken'; then
#       echo "This won't print"
#   else
#       echo "Invalid JSON detected"
#   fi
#
#   # Empty string is invalid JSON
#   if validate_json ''; then
#       echo "This won't print"
#   fi
#
#   # Use in pipelines
#   if cat config.json | jq . | validate_json; then
#       echo "Config file is valid"
#   fi
#
validate_json() {
    local json="$1"
    # Return failure for empty/whitespace-only input
    if [ -z "$json" ] || [ -z "${json// /}" ]; then
        return 1
    fi
    # Normalize jq exit codes: 0 stays 0, anything else becomes 1
    if echo "$json" | jq empty 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

#
# File System Utility Functions
#
# These functions provide safe, atomic file operations with error handling
# and cleanup guarantees. They use temporary files and atomic moves to prevent
# partial writes and race conditions.
#

#
# atomic_write - Atomically write content to a file with error handling
#
# Writes content to a temporary file first, sets restrictive permissions,
# then atomically moves it to the target location. This ensures that:
# - The target file is never left in a partial/corrupted state
# - Permission errors are caught before modifying the target
# - Cleanup happens automatically on any failure
#
# The temporary file uses process ID ($) for uniqueness and is created with
# restrictive permissions (600 = rw-------) to prevent information disclosure.
#
# Arguments:
#   $1 - Target file path (will be created or overwritten)
#   $2 - Content to write
#
# Returns:
#   0 on success, 1 on any error
#   Logs debug message on success, error messages on failure
#
# Examples:
#   # Write configuration file atomically
#   config='{"version": "1.0", "enabled": true}'
#   if atomic_write "/etc/app/config.json" "$config"; then
#       log_info "Configuration updated successfully"
#   else
#       log_error "Failed to update configuration"
#       exit 1
#   fi
#
#   # Write multi-line content
#   content="Line 1
#   Line 2
#   Line 3"
#   atomic_write "/tmp/output.txt" "$content"
#
#   # Use in pipeline with command substitution
#   result=$(some_command)
#   atomic_write "/var/run/state.txt" "$result" || exit 1
#
#   # Handles permission errors gracefully
#   atomic_write "/root/protected.txt" "data"  # Returns 1 if no permission
#
atomic_write() {
    local target_file="$1"
    local content="$2"
    local temp_file="${target_file}.tmp.$$"

    # Write to temp file
    echo "$content" > "$temp_file" || {
        log_error "Failed to write temp file: $temp_file"
        return 1
    }

    # Set restrictive permissions (600 = rw-------)
    chmod 600 "$temp_file" || {
        log_error "Failed to set permissions on temp file: $temp_file"
        rm -f "$temp_file"
        return 1
    }

    # Atomic move (overwrites target if exists)
    mv -f "$temp_file" "$target_file" || {
        log_error "Failed to move temp file to target: $temp_file -> $target_file"
        rm -f "$temp_file"
        return 1
    }

    log_debug "Atomic write successful: $target_file"
    return 0
}

#
# Path Validation Functions
#
# These functions provide security-hardened path validation to prevent:
# - Path traversal attacks (../, ~/)
# - Access to files outside SDD_ROOT
# - Symbolic link exploits
#
# All validation failures are logged with details for security auditing.
# Paths are resolved using realpath -m which handles non-existent paths
# and symbolic links correctly.
#

#
# validate_safe_path - Validate path doesn't contain traversal attempts
#
# Rejects paths containing:
# - ".." (directory traversal)
# - "~" (home directory expansion)
#
# This provides defense-in-depth against path traversal attacks before
# canonical path resolution. Even though realpath would resolve these,
# we explicitly reject them to catch malicious input early.
#
# Arguments:
#   $1 - Path to validate (can be relative or absolute)
#
# Returns:
#   0 if path is safe, 1 if path contains traversal attempts
#   Logs error message on validation failure
#
# Examples:
#   # Valid paths
#   validate_safe_path "/app/.sdd/tickets/PROJ-1"  # Returns 0
#   validate_safe_path "tickets/PROJ-1"            # Returns 0
#   validate_safe_path "./local/path"              # Returns 0
#
#   # Invalid paths (traversal attempts)
#   validate_safe_path "../../etc/passwd"          # Returns 1, logs error
#   validate_safe_path "../../../etc/shadow"       # Returns 1, logs error
#   validate_safe_path "~/malicious"               # Returns 1, logs error
#   validate_safe_path "/tmp/../etc/passwd"        # Returns 1, logs error
#
#   # Use in validation pipeline
#   if validate_safe_path "$user_input" && validate_path_in_sdd_root "$user_input"; then
#       process_file "$user_input"
#   else
#       log_error "Invalid path provided: $user_input"
#       exit 1
#   fi
#
validate_safe_path() {
    local path="$1"
    if [[ "$path" == *".."* ]] || [[ "$path" == *"~"* ]]; then
        log_error "Path traversal attempt detected: $path"
        return 1
    fi
    return 0
}

#
# validate_path_in_sdd_root - Validate path is within SDD_ROOT
#
# Resolves path to its canonical form and verifies it's within SDD_ROOT.
# Uses realpath -m to handle:
# - Non-existent paths (doesn't require file to exist)
# - Symbolic links (resolves to actual target)
# - Relative paths (converts to absolute)
# - Redundant separators and "." components
#
# This prevents access to files outside the SDD workspace, even through
# creative use of symlinks or relative paths.
#
# Arguments:
#   $1 - Path to validate (can be relative, absolute, or non-existent)
#
# Environment:
#   SDD_ROOT - Root directory of SDD workspace (must be set)
#
# Returns:
#   0 if path is within SDD_ROOT, 1 otherwise
#   Logs error message with resolved path on validation failure
#
# Examples:
#   export SDD_ROOT="/app/.sdd"
#
#   # Valid paths (within SDD_ROOT)
#   validate_path_in_sdd_root "/app/.sdd/tickets/PROJ-1"     # Returns 0
#   validate_path_in_sdd_root "${SDD_ROOT}/epics/EPIC-1"     # Returns 0
#   validate_path_in_sdd_root "tickets/new-ticket"           # Returns 0 (if CWD is in SDD_ROOT)
#
#   # Invalid paths (outside SDD_ROOT)
#   validate_path_in_sdd_root "/etc/passwd"                  # Returns 1, logs error
#   validate_path_in_sdd_root "/tmp/data"                    # Returns 1, logs error
#   validate_path_in_sdd_root "/app/../etc/passwd"           # Returns 1, logs error
#
#   # Handles symbolic links correctly
#   ln -s /etc/passwd /app/.sdd/tickets/link                 # Create symlink
#   validate_path_in_sdd_root "/app/.sdd/tickets/link"       # Returns 1 (resolves to /etc/passwd)
#
#   # Handles non-existent paths
#   validate_path_in_sdd_root "/app/.sdd/tickets/future"     # Returns 0 (within SDD_ROOT)
#
#   # Use in file operations
#   target_file="${SDD_ROOT}/tickets/${TICKET_ID}/plan.md"
#   if validate_safe_path "$target_file" && validate_path_in_sdd_root "$target_file"; then
#       atomic_write "$target_file" "$content"
#   else
#       log_error "Refusing to write to invalid path: $target_file"
#       exit 1
#   fi
#
validate_path_in_sdd_root() {
    local path="$1"
    local real_path
    real_path=$(realpath -m "$path" 2>/dev/null) || {
        log_error "Failed to resolve path: $path"
        return 1
    }

    if [[ "$real_path" != "${SDD_ROOT}"* ]]; then
        log_error "Path outside SDD_ROOT: $path -> $real_path"
        return 1
    fi
    return 0
}

#
# Configuration Management Functions
#
# These functions provide a centralized configuration system with:
# - JSON-based configuration file (config/default.json)
# - Environment variable overrides (whitelisted for security)
# - Comprehensive validation of all configuration values
# - Global CONFIG_* variables for easy access throughout the framework
#
# The configuration system separates operational parameters from code,
# enabling customization of retry behavior, checkpoint frequency, risk
# tolerance, and tool paths without code modifications.
#

# Global configuration variables (set by load_config)
CONFIG_SDD_ROOT=""
CONFIG_RETRY_MAX_ATTEMPTS=3
CONFIG_RETRY_INITIAL_DELAY=5
CONFIG_RETRY_BACKOFF_MULTIPLIER=2
CONFIG_CHECKPOINT_FREQUENCY="per_stage"
CONFIG_CHECKPOINT_MAX=10
CONFIG_RISK_TOLERANCE="moderate"
CONFIG_DECISION_TIMEOUT=120
CONFIG_LOG_LEVEL="info"
CONFIG_LOG_FORMAT="structured"
CONFIG_CLAUDE_PATH="claude"
CONFIG_JIRA_PATH="acli"
CONFIG_GH_PATH="gh"

#
# validate_config - Validate configuration values against schema rules
#
# Validates all configuration fields for:
# - Type correctness (integers, strings, enums)
# - Value constraints (positive numbers, enum membership)
# - Path existence (sdd_root must be a directory)
#
# Validation rules from architecture.md:
# - retry.max_attempts: positive integer
# - retry.initial_delay_seconds: positive integer
# - retry.backoff_multiplier: positive number
# - checkpoint.max_checkpoints: positive integer
# - checkpoint.frequency: enum (per_stage|per_ticket|disabled)
# - decision.risk_tolerance: enum (conservative|moderate|aggressive)
# - decision.timeout_seconds: positive integer
# - logging.level: enum (debug|info|warn|error)
# - logging.format: enum (structured|simple)
# - sdd_root: directory must exist
#
# Arguments:
#   None (operates on global CONFIG_* variables)
#
# Returns:
#   0 if all validations pass, 2 if any validation fails
#   Logs error message for each validation failure
#
# Examples:
#   # After loading config, validate it
#   load_config
#   if ! validate_config; then
#       log_error "Configuration validation failed"
#       exit 2
#   fi
#
#   # Invalid enum value triggers error
#   CONFIG_RISK_TOLERANCE="ultra-aggressive"
#   validate_config  # Returns 2, logs error about invalid enum
#
#   # Non-existent directory triggers error
#   CONFIG_SDD_ROOT="/nonexistent/path"
#   validate_config  # Returns 2, logs error about missing directory
#
#   # Negative number triggers error
#   CONFIG_RETRY_MAX_ATTEMPTS=-1
#   validate_config  # Returns 2, logs error about non-positive value
#
validate_config() {
    local errors=0

    # Validate retry.max_attempts (positive integer)
    if ! [[ "$CONFIG_RETRY_MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$CONFIG_RETRY_MAX_ATTEMPTS" -le 0 ]; then
        log_error "Invalid retry.max_attempts: must be positive integer, got '$CONFIG_RETRY_MAX_ATTEMPTS'"
        errors=$((errors + 1))
    fi

    # Validate retry.initial_delay_seconds (positive integer)
    if ! [[ "$CONFIG_RETRY_INITIAL_DELAY" =~ ^[0-9]+$ ]] || [ "$CONFIG_RETRY_INITIAL_DELAY" -le 0 ]; then
        log_error "Invalid retry.initial_delay_seconds: must be positive integer, got '$CONFIG_RETRY_INITIAL_DELAY'"
        errors=$((errors + 1))
    fi

    # Validate retry.backoff_multiplier (positive number)
    # Note: Using awk instead of bc for better portability
    if ! [[ "$CONFIG_RETRY_BACKOFF_MULTIPLIER" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid retry.backoff_multiplier: must be positive number, got '$CONFIG_RETRY_BACKOFF_MULTIPLIER'"
        errors=$((errors + 1))
    elif [ "$(echo "$CONFIG_RETRY_BACKOFF_MULTIPLIER" | awk '{if ($1 <= 0) print 1; else print 0}')" -eq 1 ]; then
        log_error "Invalid retry.backoff_multiplier: must be positive number, got '$CONFIG_RETRY_BACKOFF_MULTIPLIER'"
        errors=$((errors + 1))
    fi

    # Validate checkpoint.max_checkpoints (positive integer)
    if ! [[ "$CONFIG_CHECKPOINT_MAX" =~ ^[0-9]+$ ]] || [ "$CONFIG_CHECKPOINT_MAX" -le 0 ]; then
        log_error "Invalid checkpoint.max_checkpoints: must be positive integer, got '$CONFIG_CHECKPOINT_MAX'"
        errors=$((errors + 1))
    fi

    # Validate checkpoint.frequency (enum)
    case "$CONFIG_CHECKPOINT_FREQUENCY" in
        per_stage|per_ticket|disabled)
            # Valid values
            ;;
        *)
            log_error "Invalid checkpoint.frequency: must be per_stage|per_ticket|disabled, got '$CONFIG_CHECKPOINT_FREQUENCY'"
            errors=$((errors + 1))
            ;;
    esac

    # Validate decision.risk_tolerance (enum)
    case "$CONFIG_RISK_TOLERANCE" in
        conservative|moderate|aggressive)
            # Valid values
            ;;
        *)
            log_error "Invalid decision.risk_tolerance: must be conservative|moderate|aggressive, got '$CONFIG_RISK_TOLERANCE'"
            errors=$((errors + 1))
            ;;
    esac

    # Validate decision.timeout_seconds (positive integer)
    if ! [[ "$CONFIG_DECISION_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$CONFIG_DECISION_TIMEOUT" -le 0 ]; then
        log_error "Invalid decision.timeout_seconds: must be positive integer, got '$CONFIG_DECISION_TIMEOUT'"
        errors=$((errors + 1))
    fi

    # Validate logging.level (enum)
    case "$CONFIG_LOG_LEVEL" in
        debug|info|warn|error)
            # Valid values
            ;;
        *)
            log_error "Invalid logging.level: must be debug|info|warn|error, got '$CONFIG_LOG_LEVEL'"
            errors=$((errors + 1))
            ;;
    esac

    # Validate logging.format (enum)
    case "$CONFIG_LOG_FORMAT" in
        structured|simple)
            # Valid values
            ;;
        *)
            log_error "Invalid logging.format: must be structured|simple, got '$CONFIG_LOG_FORMAT'"
            errors=$((errors + 1))
            ;;
    esac

    # Validate sdd_root (directory must exist)
    if [ -z "$CONFIG_SDD_ROOT" ]; then
        log_error "Invalid sdd_root: must not be empty"
        errors=$((errors + 1))
    elif [ ! -d "$CONFIG_SDD_ROOT" ]; then
        log_error "Invalid sdd_root: directory does not exist: $CONFIG_SDD_ROOT"
        errors=$((errors + 1))
    fi

    # Return appropriate exit code
    if [ $errors -gt 0 ]; then
        log_error "Configuration validation failed with $errors error(s)"
        return 2
    fi

    log_debug "Configuration validation passed"
    return 0
}

#
# apply_env_overrides - Apply whitelisted environment variable overrides
#
# Allows specific environment variables to override configuration values.
# Only whitelisted variables are processed for security. After applying
# overrides, all values are re-validated to ensure they meet schema rules.
#
# Whitelisted environment variables:
# - SDD_ROOT_DIR -> CONFIG_SDD_ROOT
# - SDD_LOG_LEVEL -> CONFIG_LOG_LEVEL
# - SDD_RISK_TOLERANCE -> CONFIG_RISK_TOLERANCE
# - CLAUDE_PATH -> CONFIG_CLAUDE_PATH
#
# Arguments:
#   None (reads from environment, modifies global CONFIG_* variables)
#
# Returns:
#   0 if overrides applied and validated successfully, 2 if validation fails
#   Logs info message for each override applied
#
# Examples:
#   # Override log level for debugging
#   export SDD_LOG_LEVEL=debug
#   load_config
#   apply_env_overrides
#   # CONFIG_LOG_LEVEL is now "debug"
#
#   # Override SDD root directory
#   export SDD_ROOT_DIR=/custom/sdd/location
#   load_config
#   apply_env_overrides
#   # CONFIG_SDD_ROOT is now "/custom/sdd/location"
#
#   # Invalid override value triggers validation error
#   export SDD_RISK_TOLERANCE=invalid
#   load_config
#   apply_env_overrides  # Returns 2, logs validation error
#
#   # Non-whitelisted variables are ignored (security)
#   export MALICIOUS_VAR="evil"
#   apply_env_overrides  # Ignores MALICIOUS_VAR, returns 0
#
apply_env_overrides() {
    local overrides_applied=0

    # SDD_ROOT_DIR -> CONFIG_SDD_ROOT
    if [ -n "${SDD_ROOT_DIR:-}" ]; then
        log_info "Applying environment override: SDD_ROOT_DIR=$SDD_ROOT_DIR"
        CONFIG_SDD_ROOT="$SDD_ROOT_DIR"
        overrides_applied=$((overrides_applied + 1))
    fi

    # SDD_LOG_LEVEL -> CONFIG_LOG_LEVEL
    if [ -n "${SDD_LOG_LEVEL:-}" ]; then
        log_info "Applying environment override: SDD_LOG_LEVEL=$SDD_LOG_LEVEL"
        CONFIG_LOG_LEVEL="$SDD_LOG_LEVEL"
        overrides_applied=$((overrides_applied + 1))
    fi

    # SDD_RISK_TOLERANCE -> CONFIG_RISK_TOLERANCE
    if [ -n "${SDD_RISK_TOLERANCE:-}" ]; then
        log_info "Applying environment override: SDD_RISK_TOLERANCE=$SDD_RISK_TOLERANCE"
        CONFIG_RISK_TOLERANCE="$SDD_RISK_TOLERANCE"
        overrides_applied=$((overrides_applied + 1))
    fi

    # CLAUDE_PATH -> CONFIG_CLAUDE_PATH
    if [ -n "${CLAUDE_PATH:-}" ]; then
        log_info "Applying environment override: CLAUDE_PATH=$CLAUDE_PATH"
        CONFIG_CLAUDE_PATH="$CLAUDE_PATH"
        overrides_applied=$((overrides_applied + 1))
    fi

    if [ $overrides_applied -gt 0 ]; then
        log_debug "Applied $overrides_applied environment override(s)"
    else
        log_debug "No environment overrides applied"
    fi

    # Re-validate configuration after applying overrides
    validate_config
}

#
# load_config - Load and parse JSON configuration file
#
# Loads configuration from config/default.json, parses all values using jq,
# and sets global CONFIG_* variables. After loading, applies environment
# variable overrides and validates the final configuration.
#
# Configuration file location:
# - Searches for config/default.json relative to the script directory
# - Falls back to ${SDD_ROOT}/automation/config/default.json if SDD_ROOT is set
#
# The function performs these steps:
# 1. Locate and validate config file exists and is valid JSON
# 2. Parse all configuration values into global CONFIG_* variables
# 3. Apply whitelisted environment variable overrides
# 4. Validate final configuration against schema rules
#
# Arguments:
#   None (reads from file system and environment)
#
# Environment:
#   SDD_ROOT - Optional. Used to locate config file if set.
#
# Returns:
#   0 if configuration loaded and validated successfully
#   2 if config file missing, invalid JSON, or validation fails
#   Logs debug/info messages for successful steps, error messages for failures
#
# Global Variables Set:
#   CONFIG_SDD_ROOT - Root directory for SDD workspace
#   CONFIG_RETRY_MAX_ATTEMPTS - Maximum retry attempts for operations
#   CONFIG_RETRY_INITIAL_DELAY - Initial delay in seconds between retries
#   CONFIG_RETRY_BACKOFF_MULTIPLIER - Multiplier for exponential backoff
#   CONFIG_CHECKPOINT_FREQUENCY - Checkpoint frequency (per_stage|per_ticket|disabled)
#   CONFIG_CHECKPOINT_MAX - Maximum number of checkpoints to keep
#   CONFIG_RISK_TOLERANCE - Risk tolerance level (conservative|moderate|aggressive)
#   CONFIG_DECISION_TIMEOUT - Timeout in seconds for decision modules
#   CONFIG_LOG_LEVEL - Logging level (debug|info|warn|error)
#   CONFIG_LOG_FORMAT - Log format (structured|simple)
#   CONFIG_CLAUDE_PATH - Path to Claude CLI executable
#   CONFIG_JIRA_PATH - Path to Jira CLI executable (acli)
#   CONFIG_GH_PATH - Path to GitHub CLI executable (gh)
#
# Examples:
#   # Basic usage
#   source lib/common.sh
#   load_config || exit 2
#   echo "SDD Root: $CONFIG_SDD_ROOT"
#   echo "Max retries: $CONFIG_RETRY_MAX_ATTEMPTS"
#
#   # With environment overrides
#   export SDD_LOG_LEVEL=debug
#   export SDD_ROOT_DIR=/custom/location
#   load_config || exit 2
#   # CONFIG_LOG_LEVEL is "debug", CONFIG_SDD_ROOT is "/custom/location"
#
#   # Error handling
#   if ! load_config; then
#       echo "Failed to load configuration"
#       exit 2
#   fi
#
#   # Use in scripts
#   #!/usr/bin/env bash
#   set -euo pipefail
#   source "$(dirname "$0")/../lib/common.sh"
#   load_config || exit 2
#   echo "Configured to use Claude at: $CONFIG_CLAUDE_PATH"
#
load_config() {
    local config_file
    local config_content

    # Determine config file location
    # First try relative to script directory, then SDD_ROOT if set
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    config_file="${script_dir}/../config/default.json"

    if [ ! -f "$config_file" ] && [ -n "${SDD_ROOT:-}" ]; then
        config_file="${SDD_ROOT}/automation/config/default.json"
    fi

    # Verify config file exists
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 2
    fi

    log_debug "Loading configuration from: $config_file"

    # Read and validate JSON
    config_content=$(cat "$config_file") || {
        log_error "Failed to read configuration file: $config_file"
        return 2
    }

    if ! validate_json "$config_content"; then
        log_error "Configuration file contains invalid JSON: $config_file"
        return 2
    fi

    log_debug "Configuration file is valid JSON"

    # Parse configuration values using jq
    CONFIG_SDD_ROOT=$(extract_field "$config_content" "sdd_root")
    CONFIG_RETRY_MAX_ATTEMPTS=$(extract_field "$config_content" "retry.max_attempts")
    CONFIG_RETRY_INITIAL_DELAY=$(extract_field "$config_content" "retry.initial_delay_seconds")
    CONFIG_RETRY_BACKOFF_MULTIPLIER=$(extract_field "$config_content" "retry.backoff_multiplier")
    CONFIG_CHECKPOINT_FREQUENCY=$(extract_field "$config_content" "checkpoint.frequency")
    CONFIG_CHECKPOINT_MAX=$(extract_field "$config_content" "checkpoint.max_checkpoints")
    CONFIG_RISK_TOLERANCE=$(extract_field "$config_content" "decision.risk_tolerance")
    CONFIG_DECISION_TIMEOUT=$(extract_field "$config_content" "decision.timeout_seconds")
    CONFIG_LOG_LEVEL=$(extract_field "$config_content" "logging.level")
    CONFIG_LOG_FORMAT=$(extract_field "$config_content" "logging.format")
    # shellcheck disable=SC2034  # These are global config vars used by other scripts
    CONFIG_CLAUDE_PATH=$(extract_field "$config_content" "tools.claude_path")
    # shellcheck disable=SC2034
    CONFIG_JIRA_PATH=$(extract_field "$config_content" "tools.jira_path")
    # shellcheck disable=SC2034
    CONFIG_GH_PATH=$(extract_field "$config_content" "tools.gh_path")

    log_info "Configuration loaded from: $config_file"
    log_debug "CONFIG_SDD_ROOT=$CONFIG_SDD_ROOT"
    log_debug "CONFIG_RETRY_MAX_ATTEMPTS=$CONFIG_RETRY_MAX_ATTEMPTS"
    log_debug "CONFIG_CHECKPOINT_FREQUENCY=$CONFIG_CHECKPOINT_FREQUENCY"
    log_debug "CONFIG_RISK_TOLERANCE=$CONFIG_RISK_TOLERANCE"
    log_debug "CONFIG_LOG_LEVEL=$CONFIG_LOG_LEVEL"

    # Apply environment overrides and validate
    apply_env_overrides
}
