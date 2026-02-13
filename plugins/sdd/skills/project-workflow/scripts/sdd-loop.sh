#!/usr/bin/env bash
#
# SDD Loop Controller ("Ralph Wiggum Loop")
# Autonomous SDD workflow controller for multi-repository development
#
# Version: 2.0.0
#
# DESCRIPTION
#   Polls master-status-board.sh for recommended tasks and executes them via
#   Claude Code CLI in an automated loop. The controller continues processing
#   until no more agent-ready work remains, safety limits are reached, or a
#   phase boundary is hit.
#
# USAGE
#   sdd-loop.sh [options]
#
# OPTIONS
#   -h, --help              Show full help message and exit
#   -V, --version           Show version information and exit
#   -n, --dry-run           Preview actions without executing Claude Code
#   -v, --verbose           Enable verbose output with progress details
#   -q, --quiet             Suppress informational messages (errors only)
#   --debug                 Enable debug-level logging (very verbose)
#   --specs-root DIR        Root directory for SDD specs (default: /workspace/_SPECS/)
#   --repos-root DIR        Root directory for git repositories (default: /workspace/repos/)
#   --max-iterations N      Maximum task iterations before stopping (default: 50)
#   --max-errors N          Maximum consecutive errors before stopping (default: 3)
#   --timeout SECONDS       Task execution timeout in seconds (default: 600)
#   --poll-interval SECONDS Interval between status polls (default: 5)
#   --metrics-file FILE     Write JSON metrics to FILE at end of execution
#
# ENVIRONMENT VARIABLES
#   SDD_LOOP_SPECS_ROOT       Root directory for SDD specs (default: /workspace/_SPECS/)
#   SDD_LOOP_REPOS_ROOT       Root directory for git repositories (default: /workspace/repos/)
#   SDD_LOOP_WORKSPACE_ROOT   [DEPRECATED] Maps to SDD_LOOP_REPOS_ROOT with warning
#   SDD_LOOP_MAX_ITERATIONS   Maximum iterations (default: 50)
#   SDD_LOOP_MAX_ERRORS       Maximum consecutive errors (default: 3)
#   SDD_LOOP_TIMEOUT          Task timeout in seconds (default: 600)
#   SDD_LOOP_POLL_INTERVAL    Poll interval in seconds (default: 5)
#   SDD_LOOP_DRY_RUN          Set to "true" for dry-run mode
#   SDD_LOOP_VERBOSE          Set to "true" for verbose output
#   SDD_LOOP_QUIET            Set to "true" for quiet mode
#   SDD_LOOP_DEBUG            Set to "true" for debug output
#   SDD_LOOP_DEFAULT_LOCK_DIR Directory for lock/cache files (default: /tmp)
#
# EXIT CODES
#   0   - Success (all work completed or no work remaining)
#   1   - Error (task failure, max limits reached, missing dependencies)
#   2   - Usage error (invalid arguments or options)
#   130 - Interrupted by SIGINT (Ctrl+C)
#   143 - Terminated by SIGTERM
#
# EXAMPLES
#   # Basic usage - run against default roots
#   sdd-loop.sh
#
#   # Dry-run mode to preview actions without executing
#   sdd-loop.sh --dry-run
#
#   # Custom roots
#   sdd-loop.sh --specs-root /data/_SPECS/ --repos-root /data/repos/
#
#   # Custom safety limits for testing
#   sdd-loop.sh --max-iterations 10 --max-errors 5
#
#   # Configure via environment variables
#   export SDD_LOOP_TIMEOUT=7200
#   sdd-loop.sh
#
#   # CI/CD integration with quiet mode
#   sdd-loop.sh --quiet --max-iterations 50 || {
#       echo "Loop failed with exit code $?"
#       exit 1
#   }
#
#   # Write metrics file for monitoring
#   sdd-loop.sh --metrics-file /tmp/metrics.json
#
# INTEGRATION
#   The loop controller integrates with:
#   - master-status-board.sh: Provides recommended_action JSON
#   - Claude Code CLI: Executes /sdd:do-task commands
#   - .autogate.json: Reads agent_ready and stop_at_phase settings
#
# SEE ALSO
#   sdd-loop-examples.md - Comprehensive usage examples and patterns
#   master-status-board.sh - Status board scanner
#   See --help for full documentation.
#

set -euo pipefail

# =============================================================================
# Global Variables
# =============================================================================
#
# This section declares all global variables used by sdd-loop.sh, organized
# into four categories:
#
#   1. Script Metadata    - VERSION
#   2. Configuration Defaults - Readonly constants with fallback values
#   3. Runtime Configuration  - Configurable via env vars and CLI args
#   4. Internal State         - Runtime counters, flags, and process tracking
#
# All configuration defaults are readonly after initialization. Runtime
# configuration variables are set during main() argument parsing. Internal
# state variables are modified during loop execution and reset on exit.
# =============================================================================

#######################################
# PURPOSE: Script version identifier for --version output and metrics.
#
# Lifecycle:
#   - Initialized: At script load (constant)
#   - Modified: Never (update manually when releasing)
#   - Cleared: Never
#
# Type: string
# Constraints: Semver format (MAJOR.MINOR.PATCH). Immutable at runtime.
# Example: "2.0.0"
#######################################
VERSION="2.0.0"

# =============================================================================
# Configuration Defaults
# =============================================================================
#
# Readonly constants that provide fallback values when neither environment
# variables nor CLI arguments override them. Each default supports pre-setting
# via environment variable (checked with [[ -z ... ]]) to allow test fixtures
# and CI/CD pipelines to inject values before the script loads.
#
# All defaults become readonly after assignment. They are never modified
# during script execution.
# =============================================================================

#######################################
# PURPOSE: Default root directory for SDD spec data (epics, tickets, tasks).
#
# Lifecycle:
#   - Initialized: At script load (readonly)
#   - Modified: Never (readonly after assignment)
#   - Cleared: Never
#
# Type: string (directory path)
# Constraints: Must be an absolute path with trailing slash. Readonly.
#   Pre-settable via SDD_LOOP_DEFAULT_SPECS_ROOT env var before script load.
# Example: "/workspace/_SPECS/"
#######################################
[[ -z "${SDD_LOOP_DEFAULT_SPECS_ROOT:-}" ]] && readonly SDD_LOOP_DEFAULT_SPECS_ROOT="/workspace/_SPECS/"

#######################################
# PURPOSE: Default root directory for git repository scanning.
#
# Lifecycle:
#   - Initialized: At script load (readonly)
#   - Modified: Never (readonly after assignment)
#   - Cleared: Never
#
# Type: string (directory path)
# Constraints: Must be an absolute path with trailing slash. Readonly.
#   Pre-settable via SDD_LOOP_DEFAULT_REPOS_ROOT env var before script load.
# Example: "/workspace/repos/"
#######################################
[[ -z "${SDD_LOOP_DEFAULT_REPOS_ROOT:-}" ]] && readonly SDD_LOOP_DEFAULT_REPOS_ROOT="/workspace/repos/"

#######################################
# PURPOSE: Default safety limit for maximum task iterations before the loop
#   stops to prevent runaway execution.
#
# Lifecycle:
#   - Initialized: At script load (readonly)
#   - Modified: Never (readonly after assignment)
#   - Cleared: Never
#
# Type: integer
# Constraints: Positive integer. Readonly.
#   Pre-settable via SDD_LOOP_DEFAULT_MAX_ITERATIONS env var before script load.
# Example: 50
#######################################
[[ -z "${SDD_LOOP_DEFAULT_MAX_ITERATIONS:-}" ]] && readonly SDD_LOOP_DEFAULT_MAX_ITERATIONS=50

#######################################
# PURPOSE: Default maximum number of consecutive task execution errors
#   before the loop stops to prevent repeated failures.
#
# Lifecycle:
#   - Initialized: At script load (readonly)
#   - Modified: Never (readonly after assignment)
#   - Cleared: Never
#
# Type: integer
# Constraints: Positive integer. Readonly.
#   Pre-settable via SDD_LOOP_DEFAULT_MAX_ERRORS env var before script load.
# Example: 3
#######################################
[[ -z "${SDD_LOOP_DEFAULT_MAX_ERRORS:-}" ]] && readonly SDD_LOOP_DEFAULT_MAX_ERRORS=3

#######################################
# PURPOSE: Default task execution timeout in seconds. Claude Code invocations
#   that exceed this timeout are killed.
#
# Lifecycle:
#   - Initialized: At script load (readonly)
#   - Modified: Never (readonly after assignment)
#   - Cleared: Never
#
# Type: integer (seconds)
# Constraints: Positive integer. Readonly.
#   Pre-settable via SDD_LOOP_DEFAULT_TIMEOUT env var before script load.
# Example: 600
#######################################
[[ -z "${SDD_LOOP_DEFAULT_TIMEOUT:-}" ]] && readonly SDD_LOOP_DEFAULT_TIMEOUT=600

#######################################
# PURPOSE: Default interval in seconds between master-status-board.sh polls.
#
# Lifecycle:
#   - Initialized: At script load (readonly)
#   - Modified: Never (readonly after assignment)
#   - Cleared: Never
#
# Type: integer (seconds)
# Constraints: Non-negative integer. Readonly.
#   Pre-settable via SDD_LOOP_DEFAULT_POLL_INTERVAL env var before script load.
# Example: 5
#######################################
[[ -z "${SDD_LOOP_DEFAULT_POLL_INTERVAL:-}" ]] && readonly SDD_LOOP_DEFAULT_POLL_INTERVAL=5

#######################################
# PURPOSE: Timeout in seconds for filesystem operations (find commands).
#   Prevents indefinite hangs on NFS mounts with stale handles or network
#   issues. 30 seconds is generous for local filesystem operations (typically
#   <1 second) but protects the loop from becoming unresponsive when _SPECS/
#   or repos/ are on network-mounted filesystems.
#
# Lifecycle:
#   - Initialized: At script load (readonly)
#   - Modified: Never (readonly after assignment)
#   - Cleared: Never
#
# Type: integer (seconds)
# Constraints: Positive integer. Readonly.
#   Pre-settable via FILESYSTEM_TIMEOUT_SECONDS env var before script load.
# Example: 30
#######################################
[[ -z "${FILESYSTEM_TIMEOUT_SECONDS:-}" ]] && readonly FILESYSTEM_TIMEOUT_SECONDS=30

#######################################
# PURPOSE: Directory for lock files and cache files. Override to place
#   temporary files on a different filesystem (e.g., RAM disk, shared volume).
#
# Lifecycle:
#   - Initialized: At script load (readonly)
#   - Modified: Never (readonly after assignment)
#   - Cleared: Never
#
# Type: string (directory path)
# Constraints: Must be an absolute path to an existing, writable directory.
#   Readonly. Pre-settable via SDD_LOOP_DEFAULT_LOCK_DIR env var.
# Example: "/tmp"
#######################################
[[ -z "${SDD_LOOP_DEFAULT_LOCK_DIR:-}" ]] && readonly SDD_LOOP_DEFAULT_LOCK_DIR="/tmp"

#######################################
# PURPOSE: Circuit breaker advisory thresholds. Iteration counts at which
#   warning messages are logged. CIRCUIT_BREAKER_WARN_THRESHOLD indicates
#   longer-than-typical execution. CIRCUIT_BREAKER_CRITICAL_THRESHOLD
#   indicates approaching the default max_iterations limit (50). These are
#   advisory only and never abort the loop.
#
# Lifecycle:
#   - Initialized: At script load (readonly)
#   - Modified: Never (readonly after assignment)
#   - Cleared: Never
#
# Type: integer (iteration count)
# Constraints: Positive integers. WARN < CRITICAL < DEFAULT_MAX_ITERATIONS.
#   Readonly. Pre-settable via env vars before script load.
# Example: CIRCUIT_BREAKER_WARN_THRESHOLD=25, CIRCUIT_BREAKER_CRITICAL_THRESHOLD=40
#######################################
[[ -z "${CIRCUIT_BREAKER_WARN_THRESHOLD:-}" ]] && readonly CIRCUIT_BREAKER_WARN_THRESHOLD=25
[[ -z "${CIRCUIT_BREAKER_CRITICAL_THRESHOLD:-}" ]] && readonly CIRCUIT_BREAKER_CRITICAL_THRESHOLD=40

# =============================================================================
# Runtime Configuration (configurable via env vars and CLI args)
# =============================================================================
#
# These variables follow a three-tier precedence hierarchy:
#   CLI args (highest) > environment variables > configuration defaults (lowest)
#
# All are initialized from their environment variable (if set) at script load,
# then potentially overridden by CLI argument parsing in main(). After main()
# applies defaults, these variables are treated as effectively immutable for
# the duration of the loop.
# =============================================================================

#######################################
# PURPOSE: Root directory containing SDD spec data for all repositories.
#   Each subdirectory under this root corresponds to a repository's spec data
#   (epics, tickets, tasks).
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_SPECS_ROOT env var (may be empty)
#   - Modified: In main() via --specs-root CLI arg or default fallback
#   - Cleared: Never (always has a value after main() initialization)
#
# Type: string (directory path)
# Constraints: Must be an absolute path with trailing slash after main()
#   resolves it. Must point to an existing directory. Trailing slash is
#   enforced by main() for consistent path concatenation.
# Example: "/workspace/_SPECS/"
#######################################
SDD_LOOP_SPECS_ROOT="${SDD_LOOP_SPECS_ROOT:-}"

#######################################
# PURPOSE: Root directory containing git repositories. Each subdirectory
#   under this root is a repository parent (e.g., repos/<name>/<worktree>).
#   Used by find_git_root() to locate .git directories.
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_REPOS_ROOT env var (may be empty)
#   - Modified: In main() via --repos-root CLI arg, deprecated
#     SDD_LOOP_WORKSPACE_ROOT env var, or default fallback
#   - Cleared: Never (always has a value after main() initialization)
#
# Type: string (directory path)
# Constraints: Must be an absolute path with trailing slash after main()
#   resolves it. Must point to an existing directory.
# Example: "/workspace/repos/"
#######################################
SDD_LOOP_REPOS_ROOT="${SDD_LOOP_REPOS_ROOT:-}"

#######################################
# PURPOSE: Maximum number of task iterations before the loop stops.
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_MAX_ITERATIONS env var (may be empty)
#   - Modified: In main() via --max-iterations CLI arg or default fallback
#   - Cleared: Never
#
# Type: integer
# Constraints: Positive integer (must be > 0). Validated in main().
# Example: 50
#######################################
SDD_LOOP_MAX_ITERATIONS="${SDD_LOOP_MAX_ITERATIONS:-}"

#######################################
# PURPOSE: Maximum number of consecutive task execution errors before
#   the loop stops.
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_MAX_ERRORS env var (may be empty)
#   - Modified: In main() via --max-errors CLI arg or default fallback
#   - Cleared: Never
#
# Type: integer
# Constraints: Positive integer (must be > 0). Validated in main().
# Example: 3
#######################################
SDD_LOOP_MAX_ERRORS="${SDD_LOOP_MAX_ERRORS:-}"

#######################################
# PURPOSE: Timeout in seconds for each Claude Code task execution.
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_TIMEOUT env var (may be empty)
#   - Modified: In main() via --timeout CLI arg or default fallback
#   - Cleared: Never
#
# Type: integer (seconds)
# Constraints: Positive integer (must be > 0). Validated in main().
# Example: 600
#######################################
SDD_LOOP_TIMEOUT="${SDD_LOOP_TIMEOUT:-}"

#######################################
# PURPOSE: Interval in seconds between master-status-board.sh polls.
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_POLL_INTERVAL env var (may be empty)
#   - Modified: In main() via --poll-interval CLI arg or default fallback
#   - Cleared: Never
#
# Type: integer (seconds)
# Constraints: Non-negative integer (0 = no delay). Validated in main().
# Example: 5
#######################################
SDD_LOOP_POLL_INTERVAL="${SDD_LOOP_POLL_INTERVAL:-}"

#######################################
# PURPOSE: Dry-run mode flag. When "true", the loop logs actions that would
#   be taken without actually invoking Claude Code.
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_DRY_RUN env var (default: "false")
#   - Modified: In main() via -n/--dry-run CLI flag
#   - Cleared: Never
#
# Type: string (boolean flag)
# Constraints: "true" or "false". Case-sensitive.
# Example: "false"
#######################################
SDD_LOOP_DRY_RUN="${SDD_LOOP_DRY_RUN:-false}"

#######################################
# PURPOSE: Verbose mode flag. When "true", enables additional progress
#   detail in log output.
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_VERBOSE env var (default: "false")
#   - Modified: In main() via -v/--verbose CLI flag
#   - Cleared: Never
#
# Type: string (boolean flag)
# Constraints: "true" or "false". Case-sensitive.
# Example: "false"
#######################################
SDD_LOOP_VERBOSE="${SDD_LOOP_VERBOSE:-false}"

#######################################
# PURPOSE: Quiet mode flag. When "true", suppresses informational messages
#   (errors only).
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_QUIET env var (default: "false")
#   - Modified: In main() via -q/--quiet CLI flag
#   - Cleared: Never
#
# Type: string (boolean flag)
# Constraints: "true" or "false". Case-sensitive.
# Example: "false"
#######################################
SDD_LOOP_QUIET="${SDD_LOOP_QUIET:-false}"

#######################################
# PURPOSE: Debug mode flag. When "true", enables debug-level logging
#   (very verbose output useful for troubleshooting).
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_DEBUG env var (default: "false")
#   - Modified: In main() via --debug CLI flag
#   - Cleared: Never
#
# Type: string (boolean flag)
# Constraints: "true" or "false". Case-sensitive.
# Example: "false"
#######################################
SDD_LOOP_DEBUG="${SDD_LOOP_DEBUG:-false}"

#######################################
# PURPOSE: Log output format selector. Controls whether log messages are
#   emitted as human-readable text or machine-parseable JSON.
#
# Lifecycle:
#   - Initialized: At script load from SDD_LOOP_LOG_FORMAT env var (default: "text")
#   - Modified: In main() via --log-format CLI option
#   - Cleared: Never
#
# Type: string (enum)
# Constraints: Must be "text" or "json". Validated in main().
# Example: "text"
#######################################
SDD_LOOP_LOG_FORMAT="${SDD_LOOP_LOG_FORMAT:-text}"

# =============================================================================
# Internal State
# =============================================================================
#
# Runtime variables that track loop execution progress, process management,
# and inter-function communication. These are initialized at script load and
# modified during loop execution. All are reset or cleaned up on script exit
# via the cleanup() and signal handler functions.
# =============================================================================

#######################################
# PURPOSE: Absolute path to the directory containing this script. Used to
#   locate sibling scripts (e.g., master-status-board.sh) via $SCRIPT_DIR/.
#
# Lifecycle:
#   - Initialized: At script load via dirname/pwd resolution
#   - Modified: Never
#   - Cleared: Never
#
# Type: string (directory path)
# Constraints: Always an absolute path. Never null. Immutable after init.
# Example: "/workspace/repos/claude-code-plugins/plugins/sdd/skills/project-workflow/scripts"
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#######################################
# PURPOSE: Counts the number of main loop iterations completed. Used for
#   safety limit enforcement, circuit breaker thresholds, and metrics output.
#
# Lifecycle:
#   - Initialized: At script load (0)
#   - Modified: Incremented by 1 at the start of each loop iteration in main()
#   - Cleared: Never (reported in cleanup summary and metrics)
#
# Type: integer
# Constraints: Non-negative. Monotonically increasing.
# Example: 12
#######################################
ITERATION_COUNT=0

#######################################
# PURPOSE: Tracks the number of consecutive task execution errors. Used
#   to detect persistent failure conditions and stop the loop. Currently
#   initialized but reserved for future error-tracking logic.
#
# Lifecycle:
#   - Initialized: At script load (0)
#   - Modified: Referenced in JSON log context output
#   - Cleared: Never
#
# Type: integer
# Constraints: Non-negative.
# Example: 0
#######################################
CONSECUTIVE_ERRORS=0

#######################################
# PURPOSE: Signal-driven exit request flag. Set to "true" by SIGINT/SIGTERM
#   handlers to request a graceful loop exit at the next iteration boundary.
#
# Lifecycle:
#   - Initialized: At script load ("false")
#   - Modified: Set to "true" by handle_sigint() or handle_sigterm()
#   - Cleared: Never (once set, the loop exits)
#
# Type: string (boolean flag)
# Constraints: "true" or "false". Once set to "true", never reverts.
# Example: "false"
#######################################
EXIT_REQUESTED=false

#######################################
# PURPOSE: Exit code to use when the script terminates. Allows signal
#   handlers to set a specific exit code (e.g., 130 for SIGINT, 143 for
#   SIGTERM) that persists through cleanup.
#
# Lifecycle:
#   - Initialized: At script load (0)
#   - Modified: Set by signal handlers or main loop on error conditions
#   - Cleared: Never (used at script exit)
#
# Type: integer
# Constraints: Valid POSIX exit code (0-255). See EXIT CODES in script header.
# Example: 0 (success), 130 (SIGINT), 143 (SIGTERM)
#######################################
EXIT_CODE=0

#######################################
# PURPOSE: Counter for successfully completed task executions. Used in
#   cleanup summary output and metrics reporting.
#
# Lifecycle:
#   - Initialized: At script load (0)
#   - Modified: Incremented by 1 in main loop after successful task execution
#   - Cleared: Never (reported in cleanup summary and metrics)
#
# Type: integer
# Constraints: Non-negative. Monotonically increasing.
# Example: 5
#######################################
TASKS_COMPLETED=0

#######################################
# PURPOSE: Counter for failed task executions. Used in metrics reporting.
#
# Lifecycle:
#   - Initialized: At script load (0)
#   - Modified: Incremented by 1 in main loop after failed task execution
#   - Cleared: Never (reported in metrics)
#
# Type: integer
# Constraints: Non-negative. Monotonically increasing.
# Example: 1
#######################################
TASKS_FAILED=0

#######################################
# PURPOSE: Count of circuit breaker advisory warnings logged during
#   execution. Used in metrics output to report how many threshold
#   warnings were emitted.
#
# Lifecycle:
#   - Initialized: At script load (0)
#   - Modified: Incremented by check_circuit_breaker() when thresholds are hit
#   - Cleared: Never (reported in metrics)
#
# Type: integer
# Constraints: Non-negative. Monotonically increasing.
# Example: 2
#######################################
CIRCUIT_BREAKER_WARNINGS_LOGGED=0

#######################################
# PURPOSE: Comma-separated list of iteration numbers at which circuit
#   breaker warnings were logged. Used in metrics output JSON array.
#
# Lifecycle:
#   - Initialized: At script load (empty string)
#   - Modified: Appended to by check_circuit_breaker() when thresholds are hit
#   - Cleared: Never (reported in metrics)
#
# Type: string (comma-separated integers)
# Constraints: Empty string or comma-space separated integers.
#   Format must be valid for JSON array embedding: [${value}].
# Example: "25, 40"
#######################################
CIRCUIT_BREAKER_WARNING_ITERATIONS=""

#######################################
# PURPOSE: File path for optional JSON metrics output. When set, the
#   write_metrics() function writes execution statistics to this file
#   on exit.
#
# Lifecycle:
#   - Initialized: At script load (empty string = disabled)
#   - Modified: Set in main() via --metrics-file CLI option
#   - Cleared: Never
#
# Type: string (file path)
# Constraints: Empty string (disabled) or absolute path to a writable
#   file location. Parent directory must exist and be writable.
# Example: "/tmp/metrics.json"
#######################################
METRICS_FILE=""

#######################################
# PURPOSE: Unix epoch timestamp marking when main() began execution.
#   Used to calculate total loop duration in metrics output.
#
# Lifecycle:
#   - Initialized: At script load (empty string)
#   - Modified: Set once in main() via $(date +%s) after lock acquisition
#   - Cleared: Never
#
# Type: string (integer epoch seconds)
# Constraints: Empty until main() sets it. Once set, never modified.
# Example: "1707840000"
#######################################
START_TIME=""

#######################################
# PURPOSE: Flag to suppress cleanup output during --help/--version.
#   When set, the cleanup() function returns immediately without logging
#   the "Exiting after N iterations" summary.
#
# Lifecycle:
#   - Initialized: At script load (empty string)
#   - Modified: Set to "true" in main() when -h/--help or -V/--version is parsed
#   - Cleared: Never
#
# Type: string (boolean flag)
# Constraints: Empty string (show cleanup) or "true" (suppress cleanup).
# Example: "" (normal operation), "true" (help/version shown)
#######################################
HELP_SHOWN=""

#######################################
# PURPOSE: Poll result state variables. Set by poll_status() to communicate
#   the master-status-board.sh recommended action to the main loop.
#   These five variables form a logical group representing one poll result.
#
#   POLL_ACTION  - The recommended action (e.g., "do-task", "idle", "stop")
#   POLL_TASK    - Task ID to execute (e.g., "SDDLOOP-3.1001")
#   POLL_TICKET  - Ticket ID the task belongs to (e.g., "SDDLOOP-3")
#   POLL_SDD_ROOT - SDD root directory for the task's repository
#   POLL_REASON  - Human-readable reason for the recommendation
#
# Lifecycle:
#   - Initialized: At script load (all empty strings)
#   - Modified: Reset to empty at the start of each poll_status() call,
#     then populated from master-status-board.sh JSON output
#   - Cleared: Reset at the start of each poll_status() call
#
# Type: string
# Constraints: POLL_ACTION is empty or one of the action strings from
#   master-status-board.sh. POLL_TASK follows the TICKET-ID.NNNN format
#   when set. POLL_SDD_ROOT is an absolute path when set.
# Example:
#   POLL_ACTION="do-task"
#   POLL_TASK="SDDLOOP-3.1001"
#   POLL_TICKET="SDDLOOP-3"
#   POLL_SDD_ROOT="/workspace/_SPECS/claude-code-plugins"
#   POLL_REASON="Next agent-ready task"
#######################################
POLL_ACTION=""
POLL_TASK=""
POLL_TICKET=""
POLL_SDD_ROOT=""
POLL_REASON=""

#######################################
# PURPOSE: Phase boundary limit from .autogate.json. When set, the loop
#   stops before executing tasks beyond this phase number.
#
# Lifecycle:
#   - Initialized: At script load (empty string = no phase limit)
#   - Modified: Reset to empty at the start of each check_phase_boundary()
#     call, then set if .autogate.json contains a stop_at_phase value
#   - Cleared: Reset at the start of each check_phase_boundary() call
#
# Type: string (integer when set)
# Constraints: Empty string (no limit) or positive integer (1-9).
#   Phase numbers are extracted from task IDs (TICKET.XYYY where X is phase).
# Example: "" (no limit), "1" (stop after phase 1)
#######################################
STOP_AT_PHASE=""

#######################################
# PURPOSE: PID of the currently running Claude Code child process. Used
#   by signal handlers to terminate the Claude process during graceful
#   shutdown (SIGINT/SIGTERM).
#
# Lifecycle:
#   - Initialized: At script load (empty string = no active process)
#   - Modified: Set to background PID ($!) when Claude Code is launched
#     in execute_task(). Cleared after Claude process terminates or is killed.
#   - Cleared: Set to empty string by cleanup_claude_process() after
#     process termination, and after normal process completion
#
# Type: string (integer PID when set)
# Constraints: Empty string or valid PID. Used with kill -0 to check
#   if process is still running.
# Example: "" (no process), "12345" (active Claude process)
#######################################
CLAUDE_PID=""

#######################################
# PURPOSE: Re-entry guard for cleanup_claude_process(). Prevents multiple
#   rapid signals (e.g., double Ctrl+C) from causing concurrent cleanup
#   attempts that could race on PID management.
#
# Lifecycle:
#   - Initialized: At script load ("false")
#   - Modified: Set to "true" at entry to cleanup_claude_process(),
#     reset to "false" before each return path
#   - Cleared: Reset to "false" after cleanup completes
#
# Type: string (boolean flag)
# Constraints: "true" or "false". Must be "false" when not inside
#   cleanup_claude_process().
# Example: "false"
#######################################
CLEANUP_IN_PROGRESS=false

#######################################
# PURPOSE: Path to the temporary file used for caching find_git_root()
#   results. Maps repository names to their discovered git root paths
#   to avoid redundant filesystem scans when multiple tasks share a repo.
#
# Lifecycle:
#   - Initialized: At script load with PID-based path so subshells can
#     access it (e.g., "/tmp/sdd-loop-git-cache.12345")
#   - Modified: File created on disk by init_git_root_cache(). Entries
#     appended by find_git_root_cached() on cache misses.
#   - Cleared: File removed and variable set to empty by
#     cleanup_git_root_cache(), called from cleanup() and signal handlers
#
# Type: string (file path)
# Constraints: Absolute path under SDD_LOOP_DEFAULT_LOCK_DIR. PID suffix
#   ensures uniqueness per process. File format is one entry per line:
#   repo_name=absolute_path (e.g., "myproject=/workspace/repos/myproject/main")
# Example: "/tmp/sdd-loop-git-cache.12345"
#######################################
GIT_ROOT_CACHE_FILE="${SDD_LOOP_DEFAULT_LOCK_DIR}/sdd-loop-git-cache.$$"

#######################################
# PURPOSE: Path to the file-based cache metrics log. Each line records a
#   cache event: "H" for hit, "M" for miss. File-based approach is used
#   because find_git_root_cached() runs inside $() subshells, so in-memory
#   counters would not persist to the parent shell.
#
# Lifecycle:
#   - Initialized: At script load with PID-based path
#   - Modified: Lines appended by find_git_root_cached() on each lookup
#   - Cleared: File removed by cleanup_git_root_cache()
#
# Type: string (file path)
# Constraints: Absolute path under SDD_LOOP_DEFAULT_LOCK_DIR. PID suffix
#   ensures uniqueness per process. Format: one character per line (H or M).
# Example: "/tmp/sdd-loop-cache-metrics.12345"
#######################################
CACHE_METRICS_FILE="${SDD_LOOP_DEFAULT_LOCK_DIR}/sdd-loop-cache-metrics.$$"

#######################################
# PURPOSE: Cache hit count, read from CACHE_METRICS_FILE by
#   read_cache_metrics(). Initialized to 0 at script load for
#   safe use in write_metrics() even if read_cache_metrics() has
#   not yet been called.
#
# Lifecycle:
#   - Initialized: At script load (0)
#   - Modified: Set by read_cache_metrics() from file-based metrics
#   - Cleared: Never (reported in session summary and metrics)
#
# Type: integer
# Constraints: Non-negative.
# Example: 18
#######################################
CACHE_HITS=0

#######################################
# PURPOSE: Cache miss count, read from CACHE_METRICS_FILE by
#   read_cache_metrics(). Initialized to 0 at script load for
#   safe use in write_metrics() even if read_cache_metrics() has
#   not yet been called.
#
# Lifecycle:
#   - Initialized: At script load (0)
#   - Modified: Set by read_cache_metrics() from file-based metrics
#   - Cleared: Never (reported in session summary and metrics)
#
# Type: integer
# Constraints: Non-negative.
# Example: 2
#######################################
CACHE_MISSES=0

#######################################
# PURPOSE: Counter for cache invalidations. Tracks when cached entries
#   are cleared during cleanup or when proactive validation detects a
#   stale cached path. Cleanup invalidations increment the in-memory
#   counter directly (parent shell). Proactive invalidations write "I"
#   to CACHE_METRICS_FILE (subshell-safe) and are read by
#   read_cache_metrics().
#
# Lifecycle:
#   - Initialized: At script load (0)
#   - Modified: Incremented by cleanup_git_root_cache() when entries exist;
#     set by read_cache_metrics() from file-based "I" lines
#   - Cleared: Never (reported in session summary and metrics)
#
# Type: integer
# Constraints: Non-negative. Monotonically increasing.
# Example: 0
#######################################
CACHE_INVALIDATIONS=0

# =============================================================================
# Logging Functions
# =============================================================================

#######################################
# Format and output a JSON log entry
# Used internally by log_* functions when SDD_LOOP_LOG_FORMAT is "json"
#
# Arguments:
#   $1 - level: Log level (INFO, ERROR, WARN, VERBOSE, DEBUG)
#   $2 - message: Log message text
#
# Outputs:
#   Single-line JSON to stderr with format:
#   {"timestamp":"ISO8601","level":"LEVEL","message":"...","context":{...}}
#
# Notes:
#   - Uses jq for safe JSON string escaping
#   - Timestamp is UTC in ISO 8601 format
#   - Context object includes iteration, task_id, ticket_id, consecutive_errors
#     when those values are available
#######################################
format_json_log() {
    local level="$1"
    local message="$2"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Use jq to safely escape the message string
    local msg_json
    msg_json=$(jq -n --arg msg "$message" '$msg')

    # Build context object with available fields
    local context_fields=""

    # Add iteration count if available
    if [[ -n "${ITERATION_COUNT:-}" && "$ITERATION_COUNT" -gt 0 ]]; then
        context_fields="\"iteration\":$ITERATION_COUNT"
    fi

    # Add task_id if available
    if [[ -n "${POLL_TASK:-}" ]]; then
        if [[ -n "$context_fields" ]]; then
            context_fields="$context_fields,"
        fi
        local task_json
        task_json=$(jq -n --arg t "$POLL_TASK" '$t')
        context_fields="${context_fields}\"task_id\":$task_json"
    fi

    # Add ticket_id if available
    if [[ -n "${POLL_TICKET:-}" ]]; then
        if [[ -n "$context_fields" ]]; then
            context_fields="$context_fields,"
        fi
        local ticket_json
        ticket_json=$(jq -n --arg t "$POLL_TICKET" '$t')
        context_fields="${context_fields}\"ticket_id\":$ticket_json"
    fi

    # Add consecutive_errors if available and > 0
    if [[ -n "${CONSECUTIVE_ERRORS:-}" && "$CONSECUTIVE_ERRORS" -gt 0 ]]; then
        if [[ -n "$context_fields" ]]; then
            context_fields="$context_fields,"
        fi
        context_fields="${context_fields}\"consecutive_errors\":$CONSECUTIVE_ERRORS"
    fi

    # Build the final JSON output
    local context_json=""
    if [[ -n "$context_fields" ]]; then
        context_json=",\"context\":{$context_fields}"
    fi

    echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":$msg_json$context_json}" >&2
}

#######################################
# Log an informational message to stderr
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped message to stderr (text or JSON format)
#######################################
log_info() {
    if [[ "$SDD_LOOP_QUIET" != "true" ]]; then
        if [[ "$SDD_LOOP_LOG_FORMAT" == "json" ]]; then
            format_json_log "INFO" "$*"
        else
            echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [INFO] $*" >&2
        fi
    fi
}

#######################################
# Log an error message to stderr
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped error message to stderr (text or JSON format)
#######################################
log_error() {
    if [[ "$SDD_LOOP_LOG_FORMAT" == "json" ]]; then
        format_json_log "ERROR" "$*"
    else
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [ERROR] $*" >&2
    fi
}

#######################################
# Log a warning message to stderr
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped warning message to stderr (text or JSON format)
#######################################
log_warn() {
    if [[ "$SDD_LOOP_QUIET" != "true" ]]; then
        if [[ "$SDD_LOOP_LOG_FORMAT" == "json" ]]; then
            format_json_log "WARN" "$*"
        else
            echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [WARN] $*" >&2
        fi
    fi
}

#######################################
# Log a verbose message to stderr (only if verbose mode enabled and not quiet)
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped message to stderr if verbose mode is enabled and quiet is disabled (text or JSON format)
#######################################
log_verbose() {
    [[ "$SDD_LOOP_VERBOSE" != "true" || "$SDD_LOOP_QUIET" == "true" ]] && return
    if [[ "$SDD_LOOP_LOG_FORMAT" == "json" ]]; then
        format_json_log "VERBOSE" "$*"
    else
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [VERBOSE] $*" >&2
    fi
}

#######################################
# Log a debug message to stderr (only if debug mode enabled)
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped message to stderr if debug mode is enabled (text or JSON format)
#######################################
log_debug() {
    if [[ "$SDD_LOOP_DEBUG" == "true" ]]; then
        if [[ "$SDD_LOOP_LOG_FORMAT" == "json" ]]; then
            format_json_log "DEBUG" "$*"
        else
            echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') [DEBUG] $*" >&2
        fi
    fi
}

# =============================================================================
# Startup Health Check
# =============================================================================

#######################################
# Validate required dependencies are available
#
# Checks for jq, realpath (required) and claude (warning only).
# Provides clear error messages with installation instructions.
#
# Outputs:
#   Error messages to stderr if dependencies missing
#   Warning messages to stderr if optional tools missing
#
# Returns:
#   0 - All required dependencies available
#   1 - Required dependency missing
#######################################
check_dependencies() {
    local missing=0

    # Check jq (required for JSON parsing)
    if ! command -v jq >/dev/null 2>&1; then
        log_error "Required dependency not found: jq"
        log_error "Install with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
        missing=1
    fi

    # Check realpath (required for path canonicalization)
    if ! command -v realpath >/dev/null 2>&1; then
        log_error "Required dependency not found: realpath"
        log_error "Install with: sudo apt-get install coreutils (Ubuntu/Debian) or brew install coreutils (macOS)"
        missing=1
    fi

    # Check timeout (required for filesystem operation timeouts)
    if ! command -v timeout >/dev/null 2>&1; then
        log_error "Required command 'timeout' not found. Install GNU coreutils."
        missing=1
    fi

    # Check claude (warn only - may be dry-run mode)
    if ! command -v claude >/dev/null 2>&1; then
        log_warn "Claude Code CLI not found in PATH"
        log_warn "Script will work in dry-run mode but cannot execute tasks"
    fi

    if [ "$missing" -eq 1 ]; then
        log_error "Exiting due to missing required dependencies"
        return 1
    fi

    return 0
}

# =============================================================================
# JSON Helper Functions
# =============================================================================

#######################################
# Extract JSON field with jq, returning default if field is null/missing
# This helper reduces code duplication in JSON parsing operations.
#
# Arguments:
#   $1 - json: String containing JSON data
#   $2 - field_path: jq query path (e.g., ".recommended_action.action")
#   $3 - default: Default value if field not found or null (optional, defaults to "")
#
# Outputs:
#   Extracted field value or default to stdout
#
# Returns:
#   Always returns 0 (errors suppressed, default returned on failure)
#######################################
parse_json_field() {
    local json="$1"
    local field_path="$2"
    local default="${3:-}"
    echo "$json" | jq -r "$field_path // \"$default\"" 2>/dev/null
}

# =============================================================================
# Git Root Discovery
# =============================================================================

#######################################
# List subdirectories under a parent directory, sorted alphabetically.
# Returns a null-terminated list suitable for safe iteration over directory
# names containing spaces, newlines, or other special characters.
#
# Arguments:
#   $1 - parent_dir: Directory to list subdirectories under
#
# Outputs:
#   Null-terminated paths to subdirectories on stdout (sorted alphabetically)
#
# Returns:
#   0 - Success (even if no subdirectories found; output will be empty)
#   1 - Parent directory doesn't exist
#######################################
list_subdirectories_sorted() {
    local parent_dir="$1"

    [ -d "$parent_dir" ] || return 1

    # Use find -print0 | sort -z to produce a null-terminated, alphabetically
    # sorted list. This avoids word-splitting on directory names that contain
    # spaces, newlines, or other special characters.
    #
    # The find command is wrapped with timeout to prevent indefinite hangs
    # when the filesystem is on an NFS mount with stale handles. Output is
    # captured to a temp file so the timeout exit code is not lost to the pipe.
    local tmp_file
    tmp_file=$(mktemp) || return 1

    local find_exit=0
    timeout "$FILESYSTEM_TIMEOUT_SECONDS" find "$parent_dir" -mindepth 1 -maxdepth 1 -type d -print0 > "$tmp_file" 2>/dev/null || find_exit=$?

    if [ "$find_exit" -eq 124 ]; then
        log_error "Filesystem operation timed out after ${FILESYSTEM_TIMEOUT_SECONDS} seconds: $parent_dir"
        rm -f "$tmp_file"
        return 1
    fi

    if [ "$find_exit" -ne 0 ]; then
        log_error "Filesystem operation failed (exit code $find_exit): $parent_dir"
        rm -f "$tmp_file"
        return 1
    fi

    sort -z < "$tmp_file"
    rm -f "$tmp_file"
}

#######################################
# Select the first git root from a null-terminated candidate list.
# Prefers main checkouts (.git is a directory) over worktrees (.git is a file).
# Logs enhanced warnings when multiple git directories are found.
#
# Selection algorithm (two-pass):
#   Pass 1: Scan for .git directories (main checkouts). Since candidates arrive
#           sorted alphabetically, the first match is the alphabetically-first
#           main checkout. Alphabetical ordering guarantees deterministic,
#           stable selection so repeated runs pick the same root.
#   Pass 2: If no main checkout found, fall back to the first .git file
#           (worktree). Worktrees are less preferred because they depend on
#           a parent checkout and may have limited reflog history.
#
# Example scenario:
#   Candidates: BUGFIX-456/ (.git dir), FEATURE-123/ (.git file), myproject/ (.git dir)
#   Pass 1 finds: BUGFIX-456 (first), myproject (second) -- both are main checkouts
#   Result: BUGFIX-456 (alphabetically first main checkout)
#
# Arguments:
#   $1 - candidates_file: Path to file containing null-terminated directory paths
#   $2 - repo_name: Repository name (used in warning messages)
#
# Outputs:
#   Path to selected git root on stdout (or empty if none found)
#
# Returns:
#   0 - Git root found
#   1 - No git root found among candidates
#######################################
select_first_git_root() {
    local candidates_file="$1"
    local repo_name="$2"

    # --- Pass 1: Search for main checkouts (.git is a directory) ---
    # Main checkouts contain the full .git directory and are preferred because
    # they own the repository data directly, unlike worktrees which reference
    # a parent checkout via a .git file pointer.
    local candidate
    local found_root=""
    local all_candidates=""
    local git_dir_count=0
    # Candidates are null-terminated and pre-sorted alphabetically by
    # list_subdirectories_sorted(), so the first .git directory we find
    # is the alphabetically-first main checkout -- giving deterministic selection.
    while IFS= read -r -d '' candidate; do
        if [[ -d "$candidate/.git" ]]; then
            git_dir_count=$((git_dir_count + 1))
            # Collect all main-checkout names for the multi-root warning message
            if [ -n "$all_candidates" ]; then
                all_candidates="$all_candidates, $(basename "$candidate")"
            else
                all_candidates="$(basename "$candidate")"
            fi
            # Keep only the first match (alphabetically first due to sorted input)
            if [[ -z "$found_root" ]]; then
                found_root="${candidate%/}"
            fi
        fi
    done < "$candidates_file"

    if [[ -n "$found_root" ]]; then
        # Warn when multiple main checkouts exist so operators can investigate
        # whether the extra roots are intentional or stale clones
        if [ "$git_dir_count" -gt 1 ]; then
            log_warn "Multiple git roots found for repo: $repo_name"
            log_warn "Candidates: [$all_candidates]"
            log_warn "Selected (alphabetically first): $(basename "$found_root")"
        fi
        echo "$found_root"
        return 0
    fi

    # --- Pass 2: Fallback to worktrees (.git is a file) ---
    # A .git file indicates a worktree linked to a main checkout elsewhere.
    # Worktrees are acceptable when no main checkout exists under this repo
    # (e.g., the main checkout lives in a different directory structure).
    while IFS= read -r -d '' candidate; do
        if [[ -f "$candidate/.git" ]]; then
            echo "${candidate%/}"
            return 0
        fi
    done < "$candidates_file"

    # No git root found among any candidates
    return 1
}

#######################################
# Find the git root directory under repos/<name>/
# Orchestrates list_subdirectories_sorted() and select_first_git_root()
# to discover the git root within a repository parent directory.
#
# Selection: Alphabetically first .git directory, fallback to .git file (worktree)
#
# Arguments:
#   $1 - repos_root: Root directory for repositories (e.g., "/workspace/repos/")
#   $2 - repo_name: Name of the repository (e.g., "claude-code-plugins")
#
# Outputs:
#   Path to the git root directory on stdout
#
# Returns:
#   0 - Found a git root
#   1 - No git root found (repo_parent doesn't exist or no .git entries)
#######################################
find_git_root() {
    local repos_root="$1"
    local repo_name="$2"
    local repo_parent="${repos_root}${repo_name}"

    [[ -d "$repo_parent" ]] || return 1

    # Build sorted candidate list via helper
    local candidates_file
    candidates_file=$(mktemp) || return 1

    list_subdirectories_sorted "$repo_parent" > "$candidates_file"

    # Select first git root from candidates via helper
    local selected_root
    if selected_root=$(select_first_git_root "$candidates_file" "$repo_name"); then
        rm -f "$candidates_file"
        echo "$selected_root"
        return 0
    fi

    rm -f "$candidates_file"
    return 1
}

# =============================================================================
# Git Root Cache Management
# =============================================================================

#######################################
# Initialize the git root cache file
# Creates a temporary file for caching find_git_root() results.
# Idempotent - safe to call multiple times.
#
# Globals Set:
#   GIT_ROOT_CACHE_FILE - Path to the cache temp file
#
# Returns:
#   0 - Always succeeds
#######################################
init_git_root_cache() {
    if [ ! -f "$GIT_ROOT_CACHE_FILE" ]; then
        touch "$GIT_ROOT_CACHE_FILE"
        log_debug "init_git_root_cache: Created cache file: $GIT_ROOT_CACHE_FILE"
    fi
}

#######################################
# Clean up the git root cache file and cache metrics file
# Removes the temporary files if they exist. Counts cache entries
# before removal to track invalidations.
# Idempotent - safe to call multiple times.
#
# Globals:
#   GIT_ROOT_CACHE_FILE - Path to the cache temp file
#   CACHE_METRICS_FILE - Path to the cache metrics log file
#   CACHE_INVALIDATIONS - Incremented by number of cached entries removed
#######################################
cleanup_git_root_cache() {
    if [ -n "$GIT_ROOT_CACHE_FILE" ] && [ -f "$GIT_ROOT_CACHE_FILE" ]; then
        local entry_count
        entry_count=$(wc -l < "$GIT_ROOT_CACHE_FILE" 2>/dev/null || echo 0)
        entry_count=$(echo "$entry_count" | tr -d ' ')
        if [ "$entry_count" -gt 0 ] 2>/dev/null; then
            CACHE_INVALIDATIONS=$((CACHE_INVALIDATIONS + entry_count))
            log_debug "cleanup_git_root_cache: Invalidated $entry_count cache entries"
        fi
        rm -f "$GIT_ROOT_CACHE_FILE"
        log_debug "cleanup_git_root_cache: Removed cache file: $GIT_ROOT_CACHE_FILE"
    fi
    GIT_ROOT_CACHE_FILE=""

    # Clean up metrics file
    if [ -n "$CACHE_METRICS_FILE" ] && [ -f "$CACHE_METRICS_FILE" ]; then
        rm -f "$CACHE_METRICS_FILE"
        log_debug "cleanup_git_root_cache: Removed metrics file: $CACHE_METRICS_FILE"
    fi
    CACHE_METRICS_FILE=""
}

#######################################
# Read cache hit/miss/invalidation counts from the file-based metrics log.
# Sets CACHE_HITS and CACHE_MISSES by counting H and M lines in
# CACHE_METRICS_FILE. Also counts I (invalidation) lines from proactive
# cache validation and adds them to CACHE_INVALIDATIONS. These variables
# are set in the calling shell scope for use by print_cache_metrics()
# and write_metrics().
#
# Note: CACHE_INVALIDATIONS accumulates from two sources:
#   1. In-memory increments from cleanup_git_root_cache() (parent shell)
#   2. File-based "I" lines from proactive validation in find_git_root_cached()
#   This function adds the file-based count to the existing in-memory value,
#   then clears the file-based entries to prevent double-counting on
#   subsequent calls.
#
# Globals Set:
#   CACHE_HITS - Number of cache hits (from file, reset each call)
#   CACHE_MISSES - Number of cache misses (from file, reset each call)
#   CACHE_INVALIDATIONS - Adds file-based invalidation count to existing value
#
# Returns:
#   0 - Always succeeds
#######################################
read_cache_metrics() {
    CACHE_HITS=0
    CACHE_MISSES=0
    if [ -n "$CACHE_METRICS_FILE" ] && [ -f "$CACHE_METRICS_FILE" ]; then
        CACHE_HITS=$(grep -c "^H$" "$CACHE_METRICS_FILE" 2>/dev/null || echo 0)
        CACHE_MISSES=$(grep -c "^M$" "$CACHE_METRICS_FILE" 2>/dev/null || echo 0)
        local file_invalidations
        file_invalidations=$(grep -c "^I$" "$CACHE_METRICS_FILE" 2>/dev/null || echo 0)
        if [ "$file_invalidations" -gt 0 ] 2>/dev/null; then
            CACHE_INVALIDATIONS=$((CACHE_INVALIDATIONS + file_invalidations))
            # Remove I lines to prevent double-counting on subsequent calls
            sed -i '/^I$/d' "$CACHE_METRICS_FILE" 2>/dev/null || true
        fi
    fi
}

#######################################
# Print cache performance metrics to log
# Reads metrics from the file-based log, calculates hit rate, and displays
# summary. Uses awk for floating-point percentage calculation (POSIX-compatible).
# Handles division by zero when no lookups have occurred.
#
# Globals:
#   CACHE_METRICS_FILE - Path to cache metrics log file
#   CACHE_INVALIDATIONS - Number of cache invalidations
#
# Outputs:
#   Cache metrics logged via log_info to stderr
#
# Returns:
#   0 - Always succeeds
#######################################
print_cache_metrics() {
    read_cache_metrics
    local total_lookups=$((CACHE_HITS + CACHE_MISSES))
    local hit_rate="0.0"
    if [ "$total_lookups" -gt 0 ]; then
        hit_rate=$(awk "BEGIN {printf \"%.1f\", ($CACHE_HITS / $total_lookups) * 100}")
    fi

    log_info "Cache metrics: $CACHE_HITS/$total_lookups hits ($hit_rate%), $CACHE_MISSES misses, $CACHE_INVALIDATIONS invalidations"
}

#######################################
# Find git root with caching (wrapper around find_git_root)
# Caches successful find_git_root() results in a temp file to avoid
# redundant filesystem operations when multiple tasks share a repo.
#
# Proactive cache validation: Before returning a cached result, verifies
# the cached path still exists on disk. If the path is stale (deleted or
# moved), clears the cache entry, logs a warning, records an "I"
# (invalidation) event to CACHE_METRICS_FILE, and falls through to
# re-lookup via find_git_root().
#
# Arguments:
#   $1 - repos_root: Root directory for repositories
#   $2 - repo_name: Name of the repository
#
# Outputs:
#   Path to the git root directory on stdout (cached if available)
#   Warning to stderr if stale cache detected
#
# Returns:
#   0 - Found a git root (from cache or fresh lookup)
#   1 - No git root found (including after stale cache re-lookup)
#######################################
find_git_root_cached() {
    local repos_root="$1"
    local repo_name="$2"

    init_git_root_cache

    # Check cache first
    local cached
    cached=$(grep "^${repo_name}=" "$GIT_ROOT_CACHE_FILE" 2>/dev/null | head -1 | cut -d= -f2-)
    if [ -n "$cached" ]; then
        # Proactive validation: verify cached path still exists
        if [ -d "$cached" ]; then
            echo "H" >> "$CACHE_METRICS_FILE" 2>/dev/null || true
            log_debug "find_git_root_cached: Cache hit for repo: $repo_name"
            echo "$cached"
            return 0
        else
            # Stale cache detected - clear entry and log warning
            log_warn "Cached git root no longer exists: $cached"
            echo "I" >> "$CACHE_METRICS_FILE" 2>/dev/null || true
            # Remove stale entry from cache file
            local tmp_cache="${GIT_ROOT_CACHE_FILE}.tmp"
            grep -v "^${repo_name}=" "$GIT_ROOT_CACHE_FILE" > "$tmp_cache" 2>/dev/null || true
            mv -f "$tmp_cache" "$GIT_ROOT_CACHE_FILE" 2>/dev/null || true
            # Fall through to cache miss logic for re-lookup
        fi
    fi

    # Cache miss or stale cache - call original function
    echo "M" >> "$CACHE_METRICS_FILE" 2>/dev/null || true
    local result
    if result=$(find_git_root "$repos_root" "$repo_name"); then
        echo "${repo_name}=${result}" >> "$GIT_ROOT_CACHE_FILE"
        log_debug "find_git_root_cached: Cache miss for repo: $repo_name, cached result: $result"
        echo "$result"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Core Functions (Skeletons for Phase 1)
# =============================================================================

#######################################
# Poll master-status-board.sh for recommended action
# Invokes the master status board script to scan the workspace and
# determine the next recommended task based on autogate configuration.
#
# Arguments:
#   None (uses SDD_LOOP_SPECS_ROOT and SDD_LOOP_REPOS_ROOT globals)
#
# Globals Set:
#   POLL_ACTION   - Recommended action (e.g., "do-task", "none")
#   POLL_TASK     - Task ID to execute (e.g., "TICKET.1001")
#   POLL_TICKET   - Ticket ID containing the task
#   POLL_SDD_ROOT - SDD root directory path
#   POLL_REASON   - Human-readable reason for recommendation
#
# Outputs:
#   JSON output from master-status-board.sh to stdout
#
# Returns:
#   0 - Success (JSON parsed successfully)
#   1 - JSON parse error (jq failed or malformed JSON)
#   2 - master-status-board.sh execution failed
#
# Version Compatibility:
#   Extracts and validates the "version" field from status board JSON output.
#   Expected version: 1.0.0 (semantic versioning: MAJOR.MINOR.PATCH)
#   - Logs warning if version mismatches or is missing (falls back to "unknown")
#   - Version mismatch does NOT fail execution (graceful degradation)
#   - MAJOR changes indicate breaking schema changes
#   - MINOR changes indicate backward-compatible additions
#   - PATCH changes indicate bug fixes with no schema changes
#######################################
poll_status() {
    log_debug "poll_status: Polling status board for specs_root=$SDD_LOOP_SPECS_ROOT, repos_root=$SDD_LOOP_REPOS_ROOT"

    # Reset poll result state
    POLL_ACTION=""
    POLL_TASK=""
    POLL_TICKET=""
    POLL_SDD_ROOT=""
    POLL_REASON=""

    # Check if jq is installed (required for JSON parsing)
    if ! command -v jq &>/dev/null; then
        log_error "jq not found. Install with: apt-get install jq (Debian/Ubuntu) or brew install jq (macOS)"
        return 1
    fi

    # Build path to master-status-board.sh
    # The script is in the same directory as sdd-loop.sh
    local status_board_script="$SCRIPT_DIR/master-status-board.sh"

    # Verify script exists and is executable
    if [[ ! -f "$status_board_script" ]]; then
        log_error "master-status-board.sh not found: $status_board_script"
        return 2
    fi

    if [[ ! -x "$status_board_script" ]]; then
        # Try to make it executable, or warn user
        log_debug "poll_status: master-status-board.sh not executable, will invoke with bash"
    fi

    log_debug "poll_status: Executing: bash $status_board_script --json --specs-root $SDD_LOOP_SPECS_ROOT --repos-root $SDD_LOOP_REPOS_ROOT"

    # Execute master-status-board.sh with --json flag and two-root arguments
    local status_output
    local exit_code=0
    status_output=$(bash "$status_board_script" --json --specs-root "$SDD_LOOP_SPECS_ROOT" --repos-root "$SDD_LOOP_REPOS_ROOT" 2>&1) || exit_code=$?

    # Check if master-status-board.sh failed
    if [[ $exit_code -ne 0 ]]; then
        log_error "master-status-board.sh failed with exit code $exit_code"
        log_debug "poll_status: Output was: $status_output"
        return 2
    fi

    # Validate that output is valid JSON
    if ! echo "$status_output" | jq empty 2>/dev/null; then
        log_error "master-status-board.sh returned invalid JSON"
        log_debug "poll_status: Output was: $status_output"
        return 1
    fi

    # ==========================================================================
    # JSON Schema Validation
    # Validate required fields exist before attempting to parse them.
    # Catches malformed status board output early with clear error messages
    # instead of cryptic jq parse failures downstream.
    # ==========================================================================

    # Validate .version field exists (required for schema compatibility)
    if ! echo "$status_output" | jq -e '.version' >/dev/null 2>&1; then
        log_error "Invalid JSON from status board: missing .version field"
        log_error "Status board may be running old version or returned corrupted output"
        return 1
    fi

    # Validate .repos field exists and is an array (required for all parsing logic)
    if ! echo "$status_output" | jq -e '.repos | type == "array"' >/dev/null 2>&1; then
        log_error "Invalid JSON from status board: .repos field is not an array"
        return 1
    fi

    # ==========================================================================
    # Version Compatibility Check
    # Extract version field and validate before parsing other fields
    # ==========================================================================
    local status_version
    status_version=$(parse_json_field "$status_output" ".version" "unknown")
    local expected_version="1.0.0"

    if [[ "$status_version" != "$expected_version" ]]; then
        log_warn "Status board version mismatch: $status_version (expected $expected_version)"
        log_debug "poll_status: Version check - actual=$status_version, expected=$expected_version"
    else
        log_debug "poll_status: Version check passed - $status_version"
    fi

    # Parse JSON using helper function to extract recommended_action fields
    # The parse_json_field helper handles errors gracefully and returns defaults
    POLL_ACTION=$(parse_json_field "$status_output" ".recommended_action.action" "")
    POLL_TASK=$(parse_json_field "$status_output" ".recommended_action.task" "")
    POLL_TICKET=$(parse_json_field "$status_output" ".recommended_action.ticket" "")
    POLL_SDD_ROOT=$(parse_json_field "$status_output" ".recommended_action.sdd_root" "")
    POLL_REASON=$(parse_json_field "$status_output" ".recommended_action.reason" "")

    # Log poll results at verbose level (compact summary)
    log_verbose "Poll returned: action=$POLL_ACTION, task=$POLL_TASK"
    # Detailed breakdown follows
    if [[ -n "$POLL_TICKET" ]]; then
        log_verbose "  Ticket: $POLL_TICKET"
    fi
    if [[ -n "$POLL_SDD_ROOT" ]]; then
        log_verbose "  SDD Root: $POLL_SDD_ROOT"
    fi
    if [[ -n "$POLL_REASON" ]]; then
        log_verbose "  Reason: $POLL_REASON"
    fi

    # Output the full JSON to stdout for potential downstream use
    echo "$status_output"

    return 0
}

#######################################
# Execute a single task via Claude Code CLI
# Invokes Claude Code with the /sdd:do-task command, setting up
# the appropriate environment variables and working directory.
#
# Arguments:
#   $1 - Task ID (e.g., "TICKET-1.1001")
#   $2 - SDD root directory (e.g., "/workspace/repos/project/_SDD")
#
# Environment:
#   SDD_ROOT_DIR is set to the sdd_root parameter for Claude Code
#   Working directory is set to the git root (discovered via find_git_root)
#
# Outputs:
#   Logs execution progress to stderr
#   Claude Code output goes to stdout/stderr
#
# Returns:
#   0 on success
#   1 on error (invalid task ID, claude not found, execution failure)
#######################################
execute_task() {
    local task_id="$1"
    local sdd_root="$2"

    log_debug "execute_task: task_id=$task_id, sdd_root=$sdd_root"

    # ==========================================================================
    # Step 1: Validate task ID format (CRITICAL for security)
    # Pattern: TICKET-ID.NNNN where TICKET-ID is uppercase alphanumeric with dashes
    # Examples: SDDLOOP-3.1001, TICKET.1001, PROJECT-ABC.2005
    # ==========================================================================
    if [[ ! "$task_id" =~ ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+$ ]]; then
        log_error "Invalid task ID format: $task_id"
        return 1
    fi

    # ==========================================================================
    # Step 2: Validate sdd_root parameter
    # ==========================================================================
    if [[ -z "$sdd_root" ]]; then
        log_error "SDD root directory not specified"
        return 1
    fi

    if [[ ! -d "$sdd_root" ]]; then
        log_error "SDD root directory does not exist: $sdd_root"
        return 1
    fi

    # ==========================================================================
    # Step 2.5: Derive repo path via find_git_root()
    # Maps SDD root name to git root under repos/<name>/
    # ==========================================================================
    local repo_name
    repo_name=$(basename "$sdd_root")
    local repo_path
    repo_path=$(find_git_root_cached "$SDD_LOOP_REPOS_ROOT" "$repo_name") || {
        log_error "Cannot find git root for repo: $repo_name (under $SDD_LOOP_REPOS_ROOT$repo_name/)"
        return 1
    }

    log_debug "execute_task: repo_name=$repo_name, repo_path=$repo_path"

    # ==========================================================================
    # Step 2.6: Dual path bounds validation (defense in depth)
    # Validates sdd_root within specs root AND repo_path within repos root.
    # Prevents path traversal attacks if master-status-board returns malformed data
    # ==========================================================================
    local canonical_specs_root
    local canonical_repos_root
    local canonical_sdd_root
    local canonical_repo_path

    canonical_specs_root="$(realpath "$SDD_LOOP_SPECS_ROOT" 2>/dev/null)" || {
        log_error "Failed to resolve canonical path for specs root: $SDD_LOOP_SPECS_ROOT"
        return 1
    }
    canonical_repos_root="$(realpath "$SDD_LOOP_REPOS_ROOT" 2>/dev/null)" || {
        log_error "Failed to resolve canonical path for repos root: $SDD_LOOP_REPOS_ROOT"
        return 1
    }
    canonical_sdd_root="$(realpath "$sdd_root" 2>/dev/null)" || {
        log_error "Failed to resolve canonical path for SDD root: $sdd_root"
        return 1
    }
    canonical_repo_path="$(realpath "$repo_path" 2>/dev/null)" || {
        log_error "Failed to resolve canonical path for repo path: $repo_path"
        return 1
    }

    # Remove trailing slashes for consistent comparison
    canonical_specs_root="${canonical_specs_root%/}"
    canonical_repos_root="${canonical_repos_root%/}"
    canonical_sdd_root="${canonical_sdd_root%/}"
    canonical_repo_path="${canonical_repo_path%/}"

    log_debug "execute_task: canonical_specs_root=$canonical_specs_root"
    log_debug "execute_task: canonical_repos_root=$canonical_repos_root"
    log_debug "execute_task: canonical_sdd_root=$canonical_sdd_root"
    log_debug "execute_task: canonical_repo_path=$canonical_repo_path"

    if [[ "$canonical_sdd_root" != "$canonical_specs_root"/* ]]; then
        log_error "SDD root outside specs bounds: $sdd_root"
        return 1
    fi
    if [[ "$canonical_repo_path" != "$canonical_repos_root"/* ]]; then
        log_error "Repo path outside repos bounds: $repo_path"
        return 1
    fi

    log_debug "execute_task: Dual path bounds validation passed"

    # ==========================================================================
    # Step 4: Check dry-run mode (skip execution, just log)
    # ==========================================================================
    if [[ "$SDD_LOOP_DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute task: $task_id"
        log_info "[DRY-RUN] SDD_ROOT_DIR: $sdd_root"
        log_info "[DRY-RUN] Working directory: $repo_path"
        log_info "[DRY-RUN] Command: SDD_ROOT_DIR=\"$sdd_root\" claude --dangerously-skip-permissions -p \"/sdd:do-task $task_id\""
        return 0
    fi

    # ==========================================================================
    # Step 5: Check claude CLI availability
    # ==========================================================================
    if ! command -v claude &>/dev/null; then
        log_error "claude CLI not found. Install Claude Code from https://claude.ai/download"
        return 1
    fi

    # ==========================================================================
    # Step 5b: Check timeout command availability
    # ==========================================================================
    if ! command -v timeout &>/dev/null; then
        log_error "timeout command not found. Install GNU coreutils (apt-get install coreutils or brew install coreutils)"
        return 1
    fi

    # ==========================================================================
    # Step 6: Log execution start
    # ==========================================================================
    local task_timeout="${SDD_LOOP_TIMEOUT:-$SDD_LOOP_DEFAULT_TIMEOUT}"
    log_info "Executing task: $task_id (repo: $repo_path, timeout: ${task_timeout}s)"

    # ==========================================================================
    # Step 7: Execute claude with correct environment, working directory, and timeout
    # ==========================================================================
    local exit_code=0

    # Change to repo directory and execute claude with SDD_ROOT_DIR set
    # Using subshell to avoid changing cwd in the main script
    # Wrap with timeout command to enforce task execution time limit
    # Run in background and capture PID for cleanup on signal
    (
        cd "$repo_path" || exit 1
        timeout "$task_timeout" env SDD_ROOT_DIR="$sdd_root" claude --dangerously-skip-permissions -p "/sdd:do-task $task_id"
    ) &
    CLAUDE_PID=$!
    log_debug "execute_task: Started Claude process with PID: $CLAUDE_PID"

    # Wait for the backgrounded process to complete
    wait "$CLAUDE_PID"
    exit_code=$?

    # Clear PID after process completes (no longer running)
    log_debug "execute_task: Claude process (PID: $CLAUDE_PID) exited with code: $exit_code"
    CLAUDE_PID=""

    # ==========================================================================
    # Step 8: Log execution completion with exit code
    # ==========================================================================
    if [[ $exit_code -eq 0 ]]; then
        log_info "Task completed successfully: $task_id (exit code: $exit_code)"
    elif [[ $exit_code -eq 124 ]]; then
        log_error "Task timed out after $task_timeout seconds: $task_id"
    elif [[ $exit_code -eq 137 ]]; then
        log_error "Task killed by timeout (SIGKILL) after $task_timeout seconds: $task_id"
    else
        log_error "Task execution failed with exit code $exit_code: $task_id"
    fi

    # ==========================================================================
    # Step 9: Return exit code to caller
    # ==========================================================================
    return $exit_code
}

#######################################
# Check if phase boundary has been reached based on .autogate.json
# Reads stop_at_phase from the ticket's .autogate.json file and compares
# it with the current task's phase number.
#
# Arguments:
#   $1 - Ticket ID (e.g., "SDDLOOP-3")
#   $2 - Task ID (e.g., "SDDLOOP-3.1001")
#   $3 - SDD root directory (e.g., "/workspace/repos/project/_SDD")
#
# Globals Set:
#   STOP_AT_PHASE - The stop_at_phase value from .autogate.json (for logging)
#
# Returns:
#   0 - Continue (no limit, or current phase < stop_at_phase)
#   1 - Should stop (current phase >= stop_at_phase)
#
# Error Handling (graceful - default to continue):
#   - Missing .autogate.json: Log verbose, return 0
#   - Invalid JSON: Log warning, return 0
#   - Invalid task ID format: Log warning, return 0
#   - stop_at_phase not a number: Log warning, return 0
#
# Note: Phase extraction handles single-digit phases only (1-9).
#       Task ID format: TICKET.XYYY where X is phase number (1-9).
#       Phases 10+ would require regex update (unlikely in practice).
#######################################
check_phase_boundary() {
    local ticket_id="$1"
    local task_id="$2"
    local sdd_root="$3"

    log_debug "check_phase_boundary: ticket_id=$ticket_id, task_id=$task_id, sdd_root=$sdd_root"

    # Reset global state
    STOP_AT_PHASE=""

    # ==========================================================================
    # Step 1: Find ticket directory
    # ==========================================================================
    local ticket_dir
    ticket_dir=$(timeout "$FILESYSTEM_TIMEOUT_SECONDS" find "$sdd_root/tickets" -maxdepth 1 -type d -name "${ticket_id}_*" 2>/dev/null | head -n1)
    local find_exit=${PIPESTATUS[0]:-0}
    if [ "$find_exit" -eq 124 ]; then
        log_error "Filesystem operation timed out after ${FILESYSTEM_TIMEOUT_SECONDS} seconds: $sdd_root/tickets"
        return 0  # Continue - treat timeout as "no phase boundary" (graceful)
    fi

    if [[ -z "$ticket_dir" ]]; then
        log_verbose "check_phase_boundary: Ticket directory not found for $ticket_id"
        return 0  # Continue - no limit
    fi

    log_debug "check_phase_boundary: Found ticket directory: $ticket_dir"

    # ==========================================================================
    # Step 2: Check if .autogate.json exists
    # ==========================================================================
    local autogate_file="$ticket_dir/.autogate.json"

    if [[ ! -f "$autogate_file" ]]; then
        log_verbose "check_phase_boundary: No .autogate.json found at $autogate_file"
        return 0  # Continue - no limit
    fi

    # ==========================================================================
    # Step 3: Parse stop_at_phase from .autogate.json
    # ==========================================================================
    local stop_at_phase

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        log_warn "check_phase_boundary: jq not found, cannot parse .autogate.json"
        return 0  # Continue - no limit
    fi

    # Parse JSON and extract stop_at_phase
    # Use jq with error suppression and null handling
    # Note: Use || jq_exit_code=$? pattern to capture exit code without triggering set -e
    local jq_exit_code=0
    stop_at_phase=$(jq -r '.stop_at_phase // empty' "$autogate_file" 2>/dev/null) || jq_exit_code=$?

    if [[ $jq_exit_code -ne 0 ]]; then
        log_error "Failed to parse .autogate.json at $autogate_file (invalid JSON format). Phase boundary checking disabled - loop will continue indefinitely."
        return 0  # Continue - no limit
    fi

    # If stop_at_phase is empty or null, no limit is set
    if [[ -z "$stop_at_phase" ]]; then
        log_verbose "check_phase_boundary: stop_at_phase not set in $autogate_file"
        return 0  # Continue - no limit
    fi

    # Validate stop_at_phase is a positive integer
    if ! [[ "$stop_at_phase" =~ ^[0-9]+$ ]]; then
        log_warn "check_phase_boundary: stop_at_phase is not a valid number: $stop_at_phase"
        return 0  # Continue - no limit
    fi

    # Set global for logging
    STOP_AT_PHASE="$stop_at_phase"
    log_debug "check_phase_boundary: stop_at_phase=$stop_at_phase"

    # ==========================================================================
    # Step 4: Extract phase number from task ID
    # ==========================================================================
    # Task ID format: TICKET.XYYY where X is phase number (1-9)
    # Examples: SDDLOOP-3.1001 -> phase 1, TICKET.2005 -> phase 2
    local phase
    phase=$(echo "$task_id" | sed -n 's/.*\.\([0-9]\)[0-9]\{3\}/\1/p')

    if [[ -z "$phase" ]]; then
        log_warn "check_phase_boundary: Could not extract phase from task ID: $task_id"
        return 0  # Continue - no limit
    fi

    log_debug "check_phase_boundary: current phase=$phase, stop_at_phase=$stop_at_phase"

    # Log verbose for user visibility
    log_verbose "Checking phase boundary: phase=$phase, stop_at_phase=$stop_at_phase"

    # ==========================================================================
    # Step 5: Compare phase with stop_at_phase
    # ==========================================================================
    # Stop if current_phase >= stop_at_phase
    if [[ "$phase" -ge "$stop_at_phase" ]]; then
        log_debug "check_phase_boundary: Phase boundary reached (phase $phase >= stop_at_phase $stop_at_phase)"
        return 1  # Should stop
    fi

    log_debug "check_phase_boundary: Phase boundary not reached (phase $phase < stop_at_phase $stop_at_phase)"
    return 0  # Continue
}

# =============================================================================
# Metrics Output
# =============================================================================

#######################################
# Write execution metrics to JSON file
# Outputs machine-readable metrics for observability and monitoring.
#
# Arguments:
#   $1 - exit_code: The exit code of the script
#
# Globals:
#   METRICS_FILE - Path to metrics output file (if empty, no output)
#   START_TIME - Script start time (epoch seconds)
#   ITERATION_COUNT - Number of iterations completed
#   TASKS_COMPLETED - Number of successful task executions
#   TASKS_FAILED - Number of failed task executions
#   SDD_LOOP_SPECS_ROOT - Specs root directory
#   SDD_LOOP_REPOS_ROOT - Repos root directory
#   SDD_LOOP_MAX_ITERATIONS - Max iterations configuration
#   SDD_LOOP_MAX_ERRORS - Max errors configuration
#   SDD_LOOP_TIMEOUT - Timeout configuration
#   SDD_LOOP_POLL_INTERVAL - Poll interval configuration
#   SDD_LOOP_DRY_RUN - Dry run mode flag
#   SDD_LOOP_VERBOSE - Verbose mode flag
#   CACHE_HITS - Number of cache hits
#   CACHE_MISSES - Number of cache misses
#   CACHE_INVALIDATIONS - Number of cache invalidations
#
# Outputs:
#   Writes JSON file to METRICS_FILE path
#   Logs info/error messages to stderr
#
# Returns:
#   0 - Always returns success (non-fatal to preserve original exit code)
#######################################
write_metrics() {
    local exit_code="${1:-0}"

    # Skip if no metrics file specified
    if [[ -z "$METRICS_FILE" ]]; then
        log_debug "write_metrics: No metrics file specified, skipping"
        return 0
    fi

    log_debug "write_metrics: Writing metrics to $METRICS_FILE"

    # Calculate duration
    local end_time
    local duration_seconds
    end_time=$(date +%s)
    if [[ -n "$START_TIME" && "$START_TIME" =~ ^[0-9]+$ ]]; then
        duration_seconds=$((end_time - START_TIME))
    else
        duration_seconds=0
    fi

    # Generate ISO 8601 timestamp
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Determine dry_run boolean for JSON
    local dry_run_json="false"
    if [[ "$SDD_LOOP_DRY_RUN" == "true" ]]; then
        dry_run_json="true"
    fi

    # Determine verbose boolean for JSON
    local verbose_json="false"
    if [[ "$SDD_LOOP_VERBOSE" == "true" ]]; then
        verbose_json="true"
    fi

    # Build JSON output using printf (no jq dependency for writing)
    local json_output
    json_output=$(cat << EOF
{
  "version": "$VERSION",
  "timestamp": "$timestamp",
  "specs_root": "$SDD_LOOP_SPECS_ROOT",
  "repos_root": "$SDD_LOOP_REPOS_ROOT",
  "exit_code": $exit_code,
  "iterations": $ITERATION_COUNT,
  "tasks_completed": $TASKS_COMPLETED,
  "tasks_failed": $TASKS_FAILED,
  "duration_seconds": $duration_seconds,
  "configuration": {
    "max_iterations": ${SDD_LOOP_MAX_ITERATIONS:-$SDD_LOOP_DEFAULT_MAX_ITERATIONS},
    "max_errors": ${SDD_LOOP_MAX_ERRORS:-$SDD_LOOP_DEFAULT_MAX_ERRORS},
    "timeout": ${SDD_LOOP_TIMEOUT:-$SDD_LOOP_DEFAULT_TIMEOUT},
    "poll_interval": ${SDD_LOOP_POLL_INTERVAL:-$SDD_LOOP_DEFAULT_POLL_INTERVAL},
    "dry_run": $dry_run_json,
    "verbose": $verbose_json
  },
  "circuit_breaker": {
    "warnings_logged": $CIRCUIT_BREAKER_WARNINGS_LOGGED,
    "warning_iterations": [${CIRCUIT_BREAKER_WARNING_ITERATIONS}]
  },
  "cache": {
    "hits": $CACHE_HITS,
    "misses": $CACHE_MISSES,
    "invalidations": $CACHE_INVALIDATIONS,
    "total_lookups": $((CACHE_HITS + CACHE_MISSES)),
    "hit_rate_percent": $(if [ $((CACHE_HITS + CACHE_MISSES)) -gt 0 ]; then awk "BEGIN {printf \"%.1f\", ($CACHE_HITS / $((CACHE_HITS + CACHE_MISSES))) * 100}"; else echo "0.0"; fi)
  }
}
EOF
)

    # Write to file (best-effort, don't fail script)
    if echo "$json_output" > "$METRICS_FILE" 2>/dev/null; then
        log_info "Metrics written to: $METRICS_FILE"
    else
        log_error "Failed to write metrics to: $METRICS_FILE"
    fi

    return 0
}

# =============================================================================
# Signal Handling and Cleanup
# =============================================================================

#######################################
# Cleanup Claude Code process if running
# Terminates any running Claude Code process gracefully (SIGTERM),
# then forcefully (SIGKILL) if it doesn't exit within timeout.
# Idempotent - safe to call multiple times.
#
# Globals:
#   CLAUDE_PID - PID of currently running Claude Code process
#   CLEANUP_IN_PROGRESS - Flag to prevent re-entry
#
# Returns:
#   0 - Always returns success (cleanup is best-effort)
#######################################
cleanup_claude_process() {
    # Prevent re-entry (handles multiple rapid signals)
    if [[ "$CLEANUP_IN_PROGRESS" == "true" ]]; then
        log_debug "cleanup_claude_process: Already in progress, skipping"
        return 0
    fi
    CLEANUP_IN_PROGRESS=true

    # Check if we have a PID to clean up
    if [[ -z "$CLAUDE_PID" ]]; then
        log_debug "cleanup_claude_process: No Claude PID to clean up"
        CLEANUP_IN_PROGRESS=false
        return 0
    fi

    # Check if process is still running
    if ! kill -0 "$CLAUDE_PID" 2>/dev/null; then
        log_debug "cleanup_claude_process: Claude process (PID: $CLAUDE_PID) already terminated"
        CLAUDE_PID=""
        CLEANUP_IN_PROGRESS=false
        return 0
    fi

    # Process is running - terminate it
    log_info "Terminating Claude Code process (PID: $CLAUDE_PID)..."

    # Send SIGTERM for graceful shutdown
    kill -TERM "$CLAUDE_PID" 2>/dev/null

    # Wait up to 3 seconds for graceful exit (30 iterations x 0.1s poll)
    # Note: These cleanup timing values are implementation details, not tunable constants.
    local wait_count=0
    while [[ $wait_count -lt 30 ]]; do
        if ! kill -0 "$CLAUDE_PID" 2>/dev/null; then
            log_debug "cleanup_claude_process: Claude process terminated gracefully"
            CLAUDE_PID=""
            CLEANUP_IN_PROGRESS=false
            return 0
        fi
        sleep 0.1
        wait_count=$((wait_count + 1))
    done

    # Process still running after timeout - force kill
    if kill -0 "$CLAUDE_PID" 2>/dev/null; then
        log_warn "Claude process did not terminate gracefully, force killing..."
        kill -KILL "$CLAUDE_PID" 2>/dev/null

        # Brief wait for SIGKILL to take effect
        sleep 0.2

        if kill -0 "$CLAUDE_PID" 2>/dev/null; then
            log_error "Failed to kill Claude process (PID: $CLAUDE_PID)"
        else
            log_debug "cleanup_claude_process: Claude process killed with SIGKILL"
        fi
    fi

    CLAUDE_PID=""
    CLEANUP_IN_PROGRESS=false
    return 0
}

#######################################
# Cleanup function called on script exit
# Outputs final status summary showing iterations and tasks completed.
# Writes metrics file if configured.
# Skipped during --help/--version to avoid confusing output.
#
# Globals:
#   HELP_SHOWN - If set, suppresses cleanup output
#   ITERATION_COUNT - Number of iterations completed
#   TASKS_COMPLETED - Number of tasks successfully executed
#   TASKS_FAILED - Number of tasks that failed
#   EXIT_CODE - Exit code to report in metrics
#######################################
cleanup() {
    # Don't output during help/version
    [[ -n "$HELP_SHOWN" ]] && return

    # Clean up any running Claude process
    cleanup_claude_process

    # Report cache performance metrics (must run before cache cleanup)
    print_cache_metrics

    # Clean up git root cache and metrics files
    cleanup_git_root_cache

    # Clean up lock file (if we created it)
    if [ -n "${SDD_LOOP_LOCKFILE:-}" ] && [ -f "$SDD_LOOP_LOCKFILE" ]; then
        rm -f "$SDD_LOOP_LOCKFILE"
        log_debug "Removed lock file: $SDD_LOOP_LOCKFILE"
    fi

    # Write metrics file if configured
    write_metrics "$EXIT_CODE"

    log_info "Exiting after $ITERATION_COUNT iteration(s) ($TASKS_COMPLETED task(s) completed)"
}

#######################################
# Handle SIGINT (Ctrl+C) signal
# Cleans up Claude process, writes metrics, and exits with code 130 (conventional for SIGINT)
#######################################
handle_sigint() {
    EXIT_REQUESTED=true
    EXIT_CODE=130
    log_info "Received SIGINT (Ctrl+C), shutting down gracefully..."
    cleanup_claude_process
    print_cache_metrics
    cleanup_git_root_cache
    # Clean up lock file
    if [ -n "${SDD_LOOP_LOCKFILE:-}" ] && [ -f "$SDD_LOOP_LOCKFILE" ]; then
        rm -f "$SDD_LOOP_LOCKFILE"
    fi
    write_metrics "$EXIT_CODE"
    exit 130
}

#######################################
# Handle SIGTERM signal
# Cleans up Claude process, writes metrics, and exits with code 143 (conventional for SIGTERM)
#######################################
handle_sigterm() {
    EXIT_REQUESTED=true
    EXIT_CODE=143
    log_info "Received SIGTERM, shutting down gracefully..."
    cleanup_claude_process
    print_cache_metrics
    cleanup_git_root_cache
    # Clean up lock file
    if [ -n "${SDD_LOOP_LOCKFILE:-}" ] && [ -f "$SDD_LOOP_LOCKFILE" ]; then
        rm -f "$SDD_LOOP_LOCKFILE"
    fi
    write_metrics "$EXIT_CODE"
    exit 143
}

# Set up trap handlers at script load time
trap cleanup EXIT
trap handle_sigint SIGINT INT
trap handle_sigterm SIGTERM TERM

# =============================================================================
# Circuit Breaker (Advisory Safety Monitoring)
# =============================================================================

#######################################
# Check iteration count and log advisory warnings at thresholds
# This is an advisory-only function that monitors loop execution duration
# and logs warnings at predefined thresholds. It NEVER aborts the loop -
# it only provides visibility into long-running executions.
#
# Globals:
#   ITERATION_COUNT - Current iteration count from main loop
#
# Outputs:
#   Logs warning messages to stderr at threshold iterations
#
# Returns:
#   0 - Always returns success (advisory only, never aborts)
#
# Thresholds:
#   25 - First warning: indicates loop is running longer than typical
#   40 - Second warning: approaching max_iterations (default 50)
#######################################
circuit_breaker_check() {
    # Advisory warnings based on iteration count
    # Uses existing ITERATION_COUNT from main loop

    # Threshold 1: CIRCUIT_BREAKER_WARN_THRESHOLD iterations - indicates longer-than-typical execution
    if [ "$ITERATION_COUNT" -eq "$CIRCUIT_BREAKER_WARN_THRESHOLD" ]; then
        log_warn "Circuit breaker: Long-running loop detected (iteration $ITERATION_COUNT)"
        # Track warning for metrics
        CIRCUIT_BREAKER_WARNINGS_LOGGED=$((CIRCUIT_BREAKER_WARNINGS_LOGGED + 1))
        if [ -n "$CIRCUIT_BREAKER_WARNING_ITERATIONS" ]; then
            CIRCUIT_BREAKER_WARNING_ITERATIONS="${CIRCUIT_BREAKER_WARNING_ITERATIONS}, $ITERATION_COUNT"
        else
            CIRCUIT_BREAKER_WARNING_ITERATIONS="$ITERATION_COUNT"
        fi
    fi

    # Threshold 2: CIRCUIT_BREAKER_CRITICAL_THRESHOLD iterations - approaching default max_iterations
    if [ "$ITERATION_COUNT" -eq "$CIRCUIT_BREAKER_CRITICAL_THRESHOLD" ]; then
        log_warn "Circuit breaker: Extended loop execution (iteration $ITERATION_COUNT, approaching max_iterations)"
        # Track warning for metrics
        CIRCUIT_BREAKER_WARNINGS_LOGGED=$((CIRCUIT_BREAKER_WARNINGS_LOGGED + 1))
        if [ -n "$CIRCUIT_BREAKER_WARNING_ITERATIONS" ]; then
            CIRCUIT_BREAKER_WARNING_ITERATIONS="${CIRCUIT_BREAKER_WARNING_ITERATIONS}, $ITERATION_COUNT"
        else
            CIRCUIT_BREAKER_WARNING_ITERATIONS="$ITERATION_COUNT"
        fi
    fi

    # Always continue - circuit breaker is advisory only
    return 0
}

# =============================================================================
# Help and Usage
# =============================================================================

#######################################
# Show usage information
# Outputs:
#   Help text to stdout
#######################################
show_usage() {
    cat << 'EOF'
SDD Loop Controller v2.0.0 - Autonomous SDD workflow controller

DESCRIPTION
    The SDD Loop Controller ("Ralph Wiggum Loop") is an autonomous workflow
    controller that polls master-status-board.sh for recommended tasks and
    executes them via Claude Code CLI.

    The controller uses a two-root model:
    - Specs root: Contains SDD data directories (_SPECS/<name>/)
    - Repos root: Contains git repositories (repos/<name>/<git-dir>/)

    Expected directory structure:
        specs-root/
            <repo-name>/
                tickets/
                    <TICKET-ID>_<slug>/
                        tasks/
                            <TASK-ID>_<slug>.md
        repos-root/
            <repo-name>/
                <git-dir>/
                    .git/

    Warnings are logged (non-blocking) if:
    - specs-root is empty (no subdirectories found)
    - specs-root and repos-root point to the same directory

    The controller continues processing tasks until:
    - No more agent-ready work remains (action: "none")
    - Maximum iterations reached (safety limit)
    - Maximum consecutive errors reached
    - Stop-at-phase boundary reached
    - Interrupted by signal (SIGINT/SIGTERM)

USAGE
    sdd-loop.sh [options]

OPTIONS
    -h, --help
        Show this help message and exit.

    -V, --version
        Show version information and exit.

    -n, --dry-run
        Preview mode: log actions without executing Claude Code.
        Useful for testing and verification.

    -v, --verbose
        Enable verbose output with additional progress details.

    -q, --quiet
        Suppress informational messages, show only errors.

    --specs-root DIR
        Root directory for SDD specs data.
        Priority: --specs-root > SDD_LOOP_SPECS_ROOT env var > default
        Default: /workspace/_SPECS/

    --repos-root DIR
        Root directory for git repositories.
        Priority: --repos-root > SDD_LOOP_REPOS_ROOT env var > default
        Default: /workspace/repos/

    --max-iterations N
        Maximum number of task iterations before stopping.
        Default: 50. Must be a positive integer.
        Loop exits with code 1 when limit is reached.

    --max-errors N
        Maximum consecutive errors before stopping.
        Default: 3. Must be a positive integer.
        Counter resets to 0 on successful task execution.
        Loop exits with code 1 when limit is reached.

    --timeout SECONDS
        Task execution timeout in seconds.
        Default: 600 (10 minutes). Must be a positive integer.
        Timeout uses GNU coreutils timeout command.
        Exit code 124 indicates timeout occurred.

    --poll-interval SECONDS
        Interval between status board polls in seconds.
        Default: 5.
        [Phase 2 - not yet implemented]

    --metrics-file FILE
        Write machine-readable JSON metrics to FILE at end of execution.
        Useful for monitoring, trending, and CI/CD integration.
        Metrics include: iterations, tasks_completed, tasks_failed,
        duration_seconds, exit_code, timestamp, and configuration.
        File write is non-fatal (script continues on write failure).
        Parent directory must exist and be writable.

    --debug
        Enable debug-level logging (very verbose).

    --log-format FORMAT
        Set log output format: "text" (default) or "json".
        Text format: [YYYY-MM-DD HH:MM:SS] [LEVEL] message
        JSON format: {"timestamp":"ISO8601","level":"LEVEL","message":"...","context":{...}}
        JSON output includes optional context object with iteration, task_id,
        ticket_id, and consecutive_errors when available.
        Useful for log aggregation systems (ELK, CloudWatch, Datadog).

ENVIRONMENT VARIABLES
    SDD_LOOP_SPECS_ROOT
        Root directory for SDD specs data (default: /workspace/_SPECS/).
        Overridden by --specs-root.

    SDD_LOOP_REPOS_ROOT
        Root directory for git repositories (default: /workspace/repos/).
        Overridden by --repos-root.

    SDD_LOOP_WORKSPACE_ROOT
        [DEPRECATED] Maps to SDD_LOOP_REPOS_ROOT with a deprecation warning.
        Use SDD_LOOP_REPOS_ROOT instead.

    SDD_LOOP_MAX_ITERATIONS
        Maximum task iterations (default: 50).
        Overridden by --max-iterations.

    SDD_LOOP_MAX_ERRORS
        Maximum consecutive errors (default: 3).
        Overridden by --max-errors.

    SDD_LOOP_TIMEOUT
        Task execution timeout in seconds (default: 600).
        Overridden by --timeout.

    SDD_LOOP_POLL_INTERVAL
        Poll interval in seconds (default: 5).
        Overridden by --poll-interval.

    SDD_LOOP_DRY_RUN
        Set to "true" for dry-run mode.
        Overridden by --dry-run.

    SDD_LOOP_VERBOSE
        Set to "true" for verbose output.
        Overridden by --verbose.

    SDD_LOOP_QUIET
        Set to "true" for quiet mode.
        Overridden by --quiet.

    SDD_LOOP_DEBUG
        Set to "true" for debug output.
        Overridden by --debug.

    SDD_LOOP_LOG_FORMAT
        Log output format: "text" (default) or "json".
        Overridden by --log-format.

CONFIGURATION HIERARCHY
    Configuration values are resolved in the following order (later overrides earlier):
    1. Built-in defaults (SDD_LOOP_DEFAULT_* constants)
    2. Environment variables (SDD_LOOP_*)
    3. Command-line arguments

EXIT CODES
    0   - Success: All work completed or no work remaining
    1   - Error: Task failure, missing dependencies, or runtime error
    2   - Usage error: Invalid arguments or options
    130 - Interrupted: Received SIGINT (Ctrl+C)
    143 - Terminated: Received SIGTERM

EXAMPLES
    # Basic usage with default roots
    sdd-loop.sh

    # Specify custom roots
    sdd-loop.sh --specs-root /data/_SPECS/ --repos-root /data/repos/

    # Dry-run mode to preview actions
    sdd-loop.sh --dry-run

    # Verbose output for debugging
    sdd-loop.sh --verbose

    # Limit iterations for testing
    sdd-loop.sh --max-iterations 5

    # Using environment variables
    SDD_LOOP_DRY_RUN=true SDD_LOOP_VERBOSE=true sdd-loop.sh

    # Quiet mode for CI/CD pipelines
    sdd-loop.sh --quiet

    # JSON logging for log aggregation
    sdd-loop.sh --log-format json

    # JSON logging with environment variable
    SDD_LOOP_LOG_FORMAT=json sdd-loop.sh

    # Write metrics file for monitoring and CI/CD
    sdd-loop.sh --metrics-file /tmp/sdd-metrics.json

    # Combine with dry-run to test metrics output
    sdd-loop.sh --dry-run --metrics-file /tmp/metrics.json --max-iterations 5

INTEGRATION
    The loop controller integrates with:
    - master-status-board.sh: Provides recommended_action JSON
    - Claude Code CLI: Executes /sdd:do-task commands
    - .autogate.json: Reads agent_ready and stop_at_phase settings

    Typical workflow:
    1. Enable agent mode: sdd:mark-ready TICKET --agent
    2. Run loop: sdd-loop.sh
    3. Monitor logs for progress
    4. Review completed work

SINGLE INSTANCE
    Only one sdd-loop instance can run per specs-root at a time. If a
    second instance is started against the same specs-root, it exits
    immediately with exit code 1 and an error message. This prevents
    race conditions such as executing the same task twice or concurrent
    git modifications. Different specs-root paths use separate lockfiles,
    so multiple instances with different roots can run concurrently.

SAFETY FEATURES
    Circuit Breaker (Advisory-Only)
        Logs warnings at iteration thresholds but NEVER aborts automatically:
        - Iteration 25: "Long-running loop detected" (informational)
        - Iteration 40: "Extended loop execution" (elevated warning)

        Loop only stops at legitimate milestones (no work remaining,
        max iterations, stop_at_phase, or user interruption).

        Metrics JSON includes circuit_breaker section with warnings_logged
        count and warning_iterations array for post-execution analysis.

    Catastrophic Command Filter
        Claude Code hooks block 3 catastrophic command patterns:
        - Root deletion: rm -rf / or rm -rf /*
        - Root permission: chmod -R 777 / or chmod -R 777 /*
        - Disk wiping: dd to /dev/sd* devices

        Safe commands like rm -rf /tmp/* are allowed. Blocked commands
        receive clear error messages explaining the catastrophic risk.

SEE ALSO
    master-status-board.sh - Status board scanner
    sdd:mark-ready - Enable/disable agent processing
    sdd:do-task - Manual task execution

EOF
}

#######################################
# Show version information
# Outputs:
#   Version string to stdout
#######################################
show_version() {
    echo "sdd-loop.sh version $VERSION"
}

# =============================================================================
# Main Function
# =============================================================================

#######################################
# Main entry point
# Arguments:
#   $@ - Command line arguments
#######################################
main() {

    # Set up signal handlers
    trap handle_sigint SIGINT
    trap handle_sigterm SIGTERM

    # Validate required dependencies before proceeding
    check_dependencies || exit 1

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                HELP_SHOWN=true
                show_usage
                exit 0
                ;;
            -V|--version)
                HELP_SHOWN=true
                show_version
                exit 0
                ;;
            -n|--dry-run)
                SDD_LOOP_DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                SDD_LOOP_VERBOSE="true"
                shift
                ;;
            -q|--quiet)
                SDD_LOOP_QUIET="true"
                shift
                ;;
            --debug)
                SDD_LOOP_DEBUG="true"
                shift
                ;;
            --log-format)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --log-format requires a value"
                    exit 2
                fi
                if [[ "$2" != "text" && "$2" != "json" ]]; then
                    log_error "Option --log-format requires 'text' or 'json' (got: '$2')"
                    exit 2
                fi
                SDD_LOOP_LOG_FORMAT="$2"
                shift 2
                ;;
            --specs-root)
                if [[ $# -lt 2 ]]; then
                    log_error "Option --specs-root requires a directory path"
                    exit 2
                fi
                SDD_LOOP_SPECS_ROOT="$2"
                if [ -z "$SDD_LOOP_SPECS_ROOT" ]; then
                    log_error "Error: --specs-root cannot be empty"
                    exit 1
                fi
                shift 2
                ;;
            --repos-root)
                if [[ $# -lt 2 ]]; then
                    log_error "Option --repos-root requires a directory path"
                    exit 2
                fi
                SDD_LOOP_REPOS_ROOT="$2"
                if [ -z "$SDD_LOOP_REPOS_ROOT" ]; then
                    log_error "Error: --repos-root cannot be empty"
                    exit 1
                fi
                shift 2
                ;;
            --max-iterations)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --max-iterations requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --max-iterations requires a positive integer (got: '$2')"
                    exit 2
                fi
                if [[ "$2" -eq 0 ]]; then
                    log_error "Option --max-iterations requires a positive integer greater than zero (got: $2)"
                    exit 2
                fi
                SDD_LOOP_MAX_ITERATIONS="$2"
                shift 2
                ;;
            --max-errors)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --max-errors requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --max-errors requires a positive integer (got: '$2')"
                    exit 2
                fi
                if [[ "$2" -eq 0 ]]; then
                    log_error "Option --max-errors requires a positive integer greater than zero (got: $2)"
                    exit 2
                fi
                SDD_LOOP_MAX_ERRORS="$2"
                shift 2
                ;;
            --timeout)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --timeout requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^-?[0-9]+$ ]]; then
                    log_error "Error: --timeout must be a positive integer"
                    exit 1
                fi
                if [ "$2" -le 0 ]; then
                    log_error "Error: --timeout must be a positive integer"
                    exit 1
                fi
                SDD_LOOP_TIMEOUT="$2"
                shift 2
                ;;
            --poll-interval)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --poll-interval requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --poll-interval requires a non-negative integer (got: '$2')"
                    exit 2
                fi
                SDD_LOOP_POLL_INTERVAL="$2"
                shift 2
                ;;
            --metrics-file)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --metrics-file requires a file path"
                    exit 2
                fi
                # Validate the parent directory exists and is writable
                local metrics_dir
                metrics_dir=$(dirname "$2")
                if [[ ! -d "$metrics_dir" ]]; then
                    log_error "Option --metrics-file: directory does not exist: $metrics_dir"
                    exit 2
                fi
                if [[ ! -w "$metrics_dir" ]]; then
                    log_error "Option --metrics-file: directory is not writable: $metrics_dir"
                    exit 2
                fi
                METRICS_FILE="$2"
                shift 2
                ;;
            -*)
                # Check for combined short options like -nv
                if [[ "$1" =~ ^-[a-zA-Z]+$ ]]; then
                    local opts="${1:1}"
                    local i=0
                    local unknown_opt=""
                    while [[ $i -lt ${#opts} ]]; do
                        local opt="${opts:$i:1}"
                        case "$opt" in
                            n) SDD_LOOP_DRY_RUN="true" ;;
                            v) SDD_LOOP_VERBOSE="true" ;;
                            q) SDD_LOOP_QUIET="true" ;;
                            h) HELP_SHOWN=true; show_usage; exit 0 ;;
                            V) HELP_SHOWN=true; show_version; exit 0 ;;
                            *)
                                unknown_opt="$opt"
                                break
                                ;;
                        esac
                        i=$((i + 1))
                    done
                    if [[ -n "$unknown_opt" ]]; then
                        log_error "Unknown option: -$unknown_opt"
                        echo "Use --help for usage information" >&2
                        exit 2
                    fi
                    shift
                else
                    log_error "Unknown option: $1"
                    echo "Use --help for usage information" >&2
                    exit 2
                fi
                ;;
            *)
                log_error "Unexpected argument: $1 (use --specs-root and --repos-root instead)"
                echo "Use --help for usage information" >&2
                exit 2
                ;;
        esac
    done

    # Apply configuration hierarchy: defaults < env vars < CLI args
    # (CLI args already set above, now apply defaults for unset values)

    # Deprecation handling: SDD_LOOP_WORKSPACE_ROOT maps to SDD_LOOP_REPOS_ROOT
    if [[ -n "${SDD_LOOP_WORKSPACE_ROOT:-}" && -z "$SDD_LOOP_REPOS_ROOT" ]]; then
        log_warn "SDD_LOOP_WORKSPACE_ROOT is deprecated; use SDD_LOOP_REPOS_ROOT instead"
        SDD_LOOP_REPOS_ROOT="$SDD_LOOP_WORKSPACE_ROOT"
    fi

    # Specs root: --specs-root > SDD_LOOP_SPECS_ROOT env var > default
    if [[ -z "$SDD_LOOP_SPECS_ROOT" ]]; then
        SDD_LOOP_SPECS_ROOT="$SDD_LOOP_DEFAULT_SPECS_ROOT"
    fi

    # Repos root: --repos-root > SDD_LOOP_REPOS_ROOT env var > default
    if [[ -z "$SDD_LOOP_REPOS_ROOT" ]]; then
        SDD_LOOP_REPOS_ROOT="$SDD_LOOP_DEFAULT_REPOS_ROOT"
    fi

    # Apply defaults for numeric options if not set
    if [[ -z "$SDD_LOOP_MAX_ITERATIONS" ]]; then
        SDD_LOOP_MAX_ITERATIONS="$SDD_LOOP_DEFAULT_MAX_ITERATIONS"
    fi
    if [[ -z "$SDD_LOOP_MAX_ERRORS" ]]; then
        SDD_LOOP_MAX_ERRORS="$SDD_LOOP_DEFAULT_MAX_ERRORS"
    fi
    if [[ -z "$SDD_LOOP_TIMEOUT" ]]; then
        SDD_LOOP_TIMEOUT="$SDD_LOOP_DEFAULT_TIMEOUT"
    fi
    if [[ -z "$SDD_LOOP_POLL_INTERVAL" ]]; then
        SDD_LOOP_POLL_INTERVAL="$SDD_LOOP_DEFAULT_POLL_INTERVAL"
    fi

    # Expand specs root to absolute path
    if [[ ! "$SDD_LOOP_SPECS_ROOT" = /* ]]; then
        SDD_LOOP_SPECS_ROOT="$(cd "$SDD_LOOP_SPECS_ROOT" 2>/dev/null && pwd)" || {
            log_error "Cannot resolve specs root path: $SDD_LOOP_SPECS_ROOT"
            exit 1
        }
    fi

    # Expand repos root to absolute path
    if [[ ! "$SDD_LOOP_REPOS_ROOT" = /* ]]; then
        SDD_LOOP_REPOS_ROOT="$(cd "$SDD_LOOP_REPOS_ROOT" 2>/dev/null && pwd)" || {
            log_error "Cannot resolve repos root path: $SDD_LOOP_REPOS_ROOT"
            exit 1
        }
    fi

    # Ensure trailing slashes for consistent path handling
    SDD_LOOP_SPECS_ROOT="${SDD_LOOP_SPECS_ROOT%/}/"
    SDD_LOOP_REPOS_ROOT="${SDD_LOOP_REPOS_ROOT%/}/"

    # Validate specs directory exists
    if [[ ! -d "$SDD_LOOP_SPECS_ROOT" ]]; then
        log_error "Specs directory does not exist: $SDD_LOOP_SPECS_ROOT"
        exit 1
    fi

    # Validate repos directory exists
    if [[ ! -d "$SDD_LOOP_REPOS_ROOT" ]]; then
        log_error "Repos directory does not exist: $SDD_LOOP_REPOS_ROOT"
        exit 1
    fi

    # ==========================================================================
    # Root Structure Validation (non-blocking warnings)
    # Warns about common configuration errors after path canonicalization.
    # These are advisory only - execution continues regardless.
    # ==========================================================================

    # Canonicalize paths for reliable comparison
    local canonical_specs_root canonical_repos_root
    canonical_specs_root="$(realpath "$SDD_LOOP_SPECS_ROOT" 2>/dev/null)" || canonical_specs_root="$SDD_LOOP_SPECS_ROOT"
    canonical_repos_root="$(realpath "$SDD_LOOP_REPOS_ROOT" 2>/dev/null)" || canonical_repos_root="$SDD_LOOP_REPOS_ROOT"

    # Check 1: Empty specs-root (no subdirectories)
    if [ -z "$(ls -A "$canonical_specs_root" 2>/dev/null)" ]; then
        log_warn "specs-root is empty (no subdirectories): $SDD_LOOP_SPECS_ROOT"
        log_warn "Expected structure: specs-root/<repo-name>/tickets/"
    fi

    # Check 2: Identical specs-root and repos-root paths
    if [ "$canonical_specs_root" = "$canonical_repos_root" ]; then
        log_warn "specs-root and repos-root are identical: $canonical_specs_root"
        log_warn "This may cause unexpected behavior. Typically they should be separate directories."
    fi

    # ==========================================================================
    # Concurrent Invocation Protection (atomic lock file creation)
    # Prevents multiple sdd-loop instances from running against the same
    # specs root, which could cause race conditions (e.g., executing the
    # same task twice or concurrent git modifications).
    #
    # Uses two-layer protection:
    #   1. Atomic file creation via `set -o noclobber` in a subshell
    #      (prevents race where two processes both see no lock and both create one)
    #   2. flock(2) advisory lock on the lock file descriptor
    #      (kernel-level lock that auto-releases when process dies)
    #
    # Stale lock detection handles the case where a previous process was
    # killed with SIGKILL (cannot be trapped, lock file left behind).
    # ==========================================================================
    readonly SDD_LOOP_LOCKFILE="${SDD_LOOP_DEFAULT_LOCK_DIR}/sdd-loop-${SDD_LOOP_SPECS_ROOT//\//_}.lock"

    # Check for stale lock file before attempting atomic creation.
    # A stale lock file is one whose PID no longer refers to a running process.
    if [ -f "$SDD_LOOP_LOCKFILE" ]; then
        local stale_pid
        stale_pid=$(cat "$SDD_LOOP_LOCKFILE" 2>/dev/null) || stale_pid=""
        if [ -n "$stale_pid" ] && ! kill -0 "$stale_pid" 2>/dev/null; then
            log_warn "Removing stale lock file (PID $stale_pid no longer running): $SDD_LOOP_LOCKFILE"
            rm -f "$SDD_LOOP_LOCKFILE"
        fi
    fi

    # Atomic lock file creation using noclobber.
    # The subshell isolates `set -o noclobber` so it does not affect the parent shell.
    # If the file already exists, the redirection fails atomically (no race window).
    if ( set -o noclobber; echo "$$" > "$SDD_LOOP_LOCKFILE" ) 2>/dev/null; then
        log_debug "Lock file created successfully: $SDD_LOOP_LOCKFILE"
    else
        log_error "Failed to create lock file (already exists or disk full): $SDD_LOOP_LOCKFILE"
        log_error "Another sdd-loop instance is already running for specs-root: $SDD_LOOP_SPECS_ROOT"
        log_error "Lockfile: $SDD_LOOP_LOCKFILE"
        exit 1
    fi

    # Validate that the lock file was actually written with our PID.
    # Guards against silent write failures (e.g., disk full after file creation).
    local written_pid
    written_pid=$(cat "$SDD_LOOP_LOCKFILE" 2>/dev/null) || written_pid=""
    if [ "$written_pid" != "$$" ]; then
        log_error "Lock file validation failed: expected PID $$, found '$written_pid'"
        log_error "Lockfile: $SDD_LOOP_LOCKFILE"
        exit 1
    fi

    # Second layer: acquire flock on the lock file descriptor.
    # This provides kernel-level locking that auto-releases when the process
    # exits (even on SIGKILL), complementing the noclobber atomic creation.
    # Uses append mode (>>) to preserve the PID content written by noclobber.
    exec 200>>"$SDD_LOOP_LOCKFILE"
    if ! flock -n 200; then
        log_error "Another sdd-loop instance is already running for specs-root: $SDD_LOOP_SPECS_ROOT"
        log_error "Lockfile: $SDD_LOOP_LOCKFILE"
        rm -f "$SDD_LOOP_LOCKFILE"
        exit 1
    fi
    log_debug "Acquired exclusive lock: $SDD_LOOP_LOCKFILE"

    # Track start time for metrics duration calculation
    START_TIME=$(date +%s)

    # Log startup configuration
    log_debug "Configuration:"
    log_debug "  Specs root: $SDD_LOOP_SPECS_ROOT"
    log_debug "  Repos root: $SDD_LOOP_REPOS_ROOT"
    log_debug "  Max iterations: $SDD_LOOP_MAX_ITERATIONS"
    log_debug "  Max errors: $SDD_LOOP_MAX_ERRORS"
    log_debug "  Timeout: $SDD_LOOP_TIMEOUT"
    log_debug "  Poll interval: $SDD_LOOP_POLL_INTERVAL"
    log_debug "  Dry run: $SDD_LOOP_DRY_RUN"
    log_debug "  Verbose: $SDD_LOOP_VERBOSE"
    log_debug "  Quiet: $SDD_LOOP_QUIET"
    log_debug "  Log format: $SDD_LOOP_LOG_FORMAT"

    log_info "SDD Loop Controller v$VERSION starting..."
    log_info "Specs root: $SDD_LOOP_SPECS_ROOT"
    log_info "Repos root: $SDD_LOOP_REPOS_ROOT"

    if [[ "$SDD_LOOP_DRY_RUN" == "true" ]]; then
        log_info "Running in DRY-RUN mode - no tasks will be executed"
    fi

    # ==========================================================================
    # Main Poll-Execute Loop
    # ==========================================================================
    # Safety limits enforced:
    # - Max iteration limit (default: 50)
    # - Consecutive error tracking (default: 3)
    # - Task execution timeout (default: 600s)
    # ==========================================================================

    local consecutive_errors=0
    local max_iterations="$SDD_LOOP_MAX_ITERATIONS"
    local max_errors="$SDD_LOOP_MAX_ERRORS"

    # Log verbose configuration
    log_verbose "Configuration: max_iterations=$max_iterations, max_errors=$max_errors, timeout=$SDD_LOOP_TIMEOUT"

    log_info "Safety limits: max_iterations=$max_iterations, max_errors=$max_errors, timeout=${SDD_LOOP_TIMEOUT}s"

    while true; do
        # Check if exit was requested via signal
        if [[ "$EXIT_REQUESTED" == "true" ]]; then
            log_info "Loop stopped: exit requested via signal"
            exit "$EXIT_CODE"
        fi

        # =======================================================================
        # Safety Check: Max Iterations
        # =======================================================================
        if [[ $ITERATION_COUNT -ge $max_iterations ]]; then
            log_warn "Reached maximum iterations ($max_iterations)"
            log_info "Loop stopped: safety limit reached after $ITERATION_COUNT iteration(s)"
            EXIT_CODE=1
            exit 1
        fi

        # Increment iteration counter (global for cleanup)
        ITERATION_COUNT=$((ITERATION_COUNT + 1))

        # Circuit breaker advisory check (logs warnings at thresholds)
        circuit_breaker_check

        # Log iteration start
        log_info "Iteration $ITERATION_COUNT/$max_iterations: polling for next task"

        # Poll status board for recommended action
        # Redirect stdout to /dev/null since poll_status outputs JSON to stdout
        # but we only need the global variables it sets
        if ! poll_status >/dev/null; then
            log_error "Polling failed at iteration $ITERATION_COUNT"
            log_info "Loop stopped: polling error"
            EXIT_CODE=1
            exit 1
        fi

        # Handle the recommended action
        case "$POLL_ACTION" in
            "none")
                log_info "No more work available (reason: ${POLL_REASON:-no tasks remaining})"
                log_info "Loop stopped: all work completed after $ITERATION_COUNT iteration(s)"
                EXIT_CODE=0
                exit 0
                ;;
            "do-task")
                log_info "Action: execute task $POLL_TASK (ticket: $POLL_TICKET)"

                # Execute the task and capture exit code
                local task_exit_code=0
                execute_task "$POLL_TASK" "$POLL_SDD_ROOT" || task_exit_code=$?

                # =============================================================
                # Error Tracking: Update consecutive error counter
                # =============================================================
                if [[ $task_exit_code -eq 0 ]]; then
                    # Success: increment tasks completed counter
                    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

                    # Reset consecutive error counter
                    if [[ $consecutive_errors -gt 0 ]]; then
                        log_verbose "Task succeeded, resetting consecutive error counter (was: $consecutive_errors)"
                    fi
                    consecutive_errors=0

                    # ==========================================================
                    # Phase Boundary Check: Stop if stop_at_phase reached
                    # Note: check_phase_boundary returns 1 (non-zero) when should stop
                    # Using if ! pattern to avoid set -e terminating on non-zero return
                    # ==========================================================
                    if ! check_phase_boundary "$POLL_TICKET" "$POLL_TASK" "$POLL_SDD_ROOT"; then
                        log_info "Phase boundary reached (stop_at_phase: $STOP_AT_PHASE)"
                        log_info "Loop stopped: phase $STOP_AT_PHASE limit reached after $ITERATION_COUNT iteration(s)"
                        EXIT_CODE=0
                        exit 0
                    fi

                    log_verbose "Task $POLL_TASK completed, continuing to next iteration"
                else
                    # Failure: increment consecutive error counter and tasks failed counter
                    consecutive_errors=$((consecutive_errors + 1))
                    TASKS_FAILED=$((TASKS_FAILED + 1))
                    log_warn "Task failed (exit code: $task_exit_code), consecutive errors: $consecutive_errors/$max_errors"

                    # ==========================================================
                    # Safety Check: Max Consecutive Errors
                    # ==========================================================
                    if [[ $consecutive_errors -ge $max_errors ]]; then
                        log_error "Reached maximum consecutive errors ($max_errors)"
                        log_info "Loop stopped: too many consecutive failures after $ITERATION_COUNT iteration(s)"
                        EXIT_CODE=1
                        exit 1
                    fi

                    log_info "Continuing despite error ($consecutive_errors/$max_errors consecutive errors)"
                fi
                ;;
            *)
                log_warn "Unknown action: $POLL_ACTION (treating as 'none')"
                log_info "Loop stopped: unknown action at iteration $ITERATION_COUNT"
                EXIT_CODE=0
                exit 0
                ;;
        esac
    done
}

# =============================================================================
# Entry Point
# =============================================================================

# Run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
