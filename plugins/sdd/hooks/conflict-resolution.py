#!/usr/bin/env python3
"""
SDD Conflict Detection and Resolution Module.

This module detects and resolves state mismatches between task markdown files
and the Claude Code Tasks API. The file is always authoritative (file wins policy).

The conflict resolution process:
1. Compare file checkbox state with Tasks API status for all tasks
2. Detect mismatches (conflicts) between the two sources
3. Log warnings for all detected conflicts
4. Return resolution data for re-hydration from file state

Design Principles:
- File is ALWAYS authoritative (source of truth)
- Tasks API state is derived from file state
- Conflicts are resolved by overwriting API with file state
- All operations fail-safe (errors don't prevent workflow)

Usage:
    # As a module
    from conflict_resolution import detect_conflicts, resolve_conflicts

    conflicts = detect_conflicts(file_states, api_states)
    if conflicts:
        resolution = resolve_conflicts(conflicts)

    # As a CLI tool (for testing)
    python conflict-resolution.py <ticket_path> <task_list_id>

Exit Codes:
    0: Success (conflicts detected and resolved, or no conflicts)
    1: Error (invalid arguments, etc.)

Output Format:
    JSON object with conflict details and resolution actions.
"""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional


# ============================================================================
# Constants and Patterns
# ============================================================================

# Debug mode environment variable
DEBUG_ENV_VAR = 'SDD_TASKS_SYNC_DEBUG'

# Task ID pattern (e.g., TASKINT.1001, AUTH.2003)
TASK_ID_PATTERN = re.compile(r'^([A-Z]+)\.(\d{4})')

# Task ID in filename (e.g., TASKINT.1001_hydration-module.md)
TASK_FILENAME_PATTERN = re.compile(r'^([A-Z]+\.\d{4})_.*\.md$')

# Status checkbox patterns (matching hydrate-tasks.py)
# Match: - [ ] **Task completed** or - [x] **Task completed** (with optional bold)
TASK_COMPLETED_PATTERN = re.compile(
    r'^[\s]*-\s*\[([xX\s])\]\s*\*{0,2}Task completed\*{0,2}',
    re.MULTILINE
)

# Code block pattern (to skip parsing inside code blocks)
CODE_BLOCK_PATTERN = re.compile(r'```[\s\S]*?```', re.MULTILINE)

# Log file for conflict resolution (for debugging)
LOG_FILE = Path("/tmp/sdd-conflict-resolution.log")


# ============================================================================
# Logging
# ============================================================================

def is_debug_mode() -> bool:
    """Check if debug mode is enabled via environment variable."""
    return os.environ.get(DEBUG_ENV_VAR, '').lower() in ('true', '1', 'yes')


def log(message: str, level: str = 'INFO') -> None:
    """
    Log message to file and optionally stderr in debug mode.

    Args:
        message: Message to log.
        level: Log level (INFO, WARNING, ERROR, DEBUG).
    """
    try:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_line = f"[{timestamp}] [{level}] {message}"

        # Always write to log file
        with open(LOG_FILE, "a") as f:
            f.write(log_line + "\n")

        # In debug mode, also output to stderr
        if is_debug_mode() or level in ('WARNING', 'ERROR'):
            print(log_line, file=sys.stderr)

    except Exception:
        pass  # Fail silently - logging should never break functionality


def debug(message: str) -> None:
    """Log debug message (only visible in debug mode)."""
    if is_debug_mode():
        log(message, 'DEBUG')


def warning(message: str) -> None:
    """Log warning message (always visible in logs, stderr in debug mode)."""
    log(message, 'WARNING')


def error(message: str) -> None:
    """Log error message (always visible)."""
    log(message, 'ERROR')


# ============================================================================
# File State Parsing
# ============================================================================

def remove_code_blocks(content: str) -> str:
    """
    Remove code blocks from markdown content to avoid parsing checkboxes in examples.

    Args:
        content: Markdown content that may contain code blocks.

    Returns:
        Content with code blocks replaced by empty strings.
    """
    return CODE_BLOCK_PATTERN.sub('', content)


def parse_file_status(content: str) -> str:
    """
    Parse the Task completed checkbox from task file content.

    Args:
        content: Full content of a task file.

    Returns:
        Status string: 'completed' or 'pending'.
    """
    # Remove code blocks to avoid parsing example checkboxes
    clean_content = remove_code_blocks(content)

    # Parse Task completed checkbox
    match = TASK_COMPLETED_PATTERN.search(clean_content)
    if match:
        checkbox_value = match.group(1).lower()
        if checkbox_value == 'x':
            return 'completed'

    return 'pending'


def extract_task_id_from_filename(filename: str) -> Optional[str]:
    """
    Extract task ID from a task filename.

    Expected format: TICKETID.NNNN_task-description.md
    E.g., TASKINT.1001_hydration-module.md -> TASKINT.1001

    Args:
        filename: Name of the task file.

    Returns:
        Task ID if found, None otherwise.
    """
    match = TASK_FILENAME_PATTERN.match(filename)
    if match:
        return match.group(1)
    return None


def discover_task_files(tasks_dir: str) -> list[tuple[str, str]]:
    """
    Discover task files in a tasks directory.

    Args:
        tasks_dir: Path to the tasks directory.

    Returns:
        List of tuples (task_id, file_path) for valid task files.
        Skips index files and files without valid task IDs.
    """
    tasks = []

    if not os.path.isdir(tasks_dir):
        return tasks

    try:
        for filename in os.listdir(tasks_dir):
            # Skip non-markdown files
            if not filename.endswith('.md'):
                continue

            # Skip index files
            if '_INDEX' in filename.upper() or filename.upper().endswith('_INDEX.MD'):
                continue

            # Extract task ID
            task_id = extract_task_id_from_filename(filename)
            if not task_id:
                continue

            file_path = os.path.join(tasks_dir, filename)
            tasks.append((task_id, file_path))

    except OSError as e:
        warning(f"Error listing tasks directory {tasks_dir}: {e}")

    # Sort by task ID for deterministic ordering
    tasks.sort(key=lambda x: x[0])
    return tasks


def get_file_states(ticket_path: str) -> dict[str, dict]:
    """
    Get current file states for all tasks in a ticket.

    Args:
        ticket_path: Path to ticket directory (must contain tasks/ subdirectory).

    Returns:
        Dictionary mapping task_id to state dict with:
            - status: 'pending' or 'completed'
            - file_path: Path to the task file
    """
    file_states = {}
    tasks_dir = os.path.join(ticket_path, 'tasks')

    task_files = discover_task_files(tasks_dir)

    for task_id, file_path in task_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            status = parse_file_status(content)
            file_states[task_id] = {
                'status': status,
                'file_path': file_path,
            }

            debug(f"File state for {task_id}: {status}")

        except (OSError, IOError) as e:
            warning(f"Could not read task file {file_path}: {e}")

    return file_states


# ============================================================================
# API State Handling
# ============================================================================

def normalize_api_status(status: str) -> str:
    """
    Normalize Tasks API status to file-comparable status.

    API statuses:
        - 'pending': Task not started
        - 'in_progress': Task being worked on (treat as pending for conflict detection)
        - 'completed': Task finished

    File statuses:
        - 'pending': Checkbox unchecked
        - 'completed': Checkbox checked

    Args:
        status: Tasks API status string.

    Returns:
        Normalized status: 'pending' or 'completed'.
    """
    if status == 'completed':
        return 'completed'
    # Both 'pending' and 'in_progress' map to 'pending' for file comparison
    return 'pending'


def parse_api_states(api_tasks: list[dict]) -> dict[str, dict]:
    """
    Parse Tasks API response into comparable state format.

    Args:
        api_tasks: List of task dictionaries from Tasks API (e.g., from TaskList).

    Returns:
        Dictionary mapping task_id to state dict with:
            - status: 'pending' or 'completed' (normalized)
            - raw_status: Original API status
            - api_id: Task ID in API (may differ from file task_id)
    """
    api_states = {}

    for task in api_tasks:
        # Extract task_id from metadata if available, otherwise from subject
        task_id = None
        metadata = task.get('metadata', {})

        if metadata and 'file_path' in metadata:
            # Extract task ID from file path in metadata
            file_path = metadata.get('file_path', '')
            filename = os.path.basename(file_path)
            task_id = extract_task_id_from_filename(filename)

        if not task_id:
            # Try to extract from subject (format: "Task TICKETID.NNNN: ...")
            subject = task.get('subject', '')
            match = TASK_ID_PATTERN.search(subject)
            if match:
                task_id = match.group(0)

        if not task_id:
            # Skip tasks we can't identify
            debug(f"Skipping unidentifiable API task: {task}")
            continue

        raw_status = task.get('status', 'pending')
        normalized_status = normalize_api_status(raw_status)

        api_states[task_id] = {
            'status': normalized_status,
            'raw_status': raw_status,
            'api_id': task.get('id', ''),
        }

        debug(f"API state for {task_id}: {raw_status} (normalized: {normalized_status})")

    return api_states


# ============================================================================
# Conflict Detection
# ============================================================================

def detect_conflicts(
    file_states: dict[str, dict],
    api_states: dict[str, dict]
) -> list[dict]:
    """
    Detect conflicts between file and API states.

    A conflict exists when the normalized status differs between file and API.

    Conflict scenarios:
        - File shows complete, API shows pending -> Conflict (file wins)
        - File shows pending, API shows complete -> Conflict (file wins)
        - File and API match -> No conflict
        - Task exists in file but not API -> Not a conflict (needs hydration)
        - Task exists in API but not file -> Orphaned (log warning)

    Args:
        file_states: Dictionary from get_file_states().
        api_states: Dictionary from parse_api_states().

    Returns:
        List of conflict dictionaries with:
            - task_id: Task identifier
            - file_status: Status from file
            - api_status: Status from API (normalized)
            - api_raw_status: Raw API status
            - file_path: Path to task file
            - resolution: 'use_file' (always, per file-wins policy)
    """
    conflicts = []

    log("--- Conflict Detection Started ---")
    debug(f"File states count: {len(file_states)}")
    debug(f"API states count: {len(api_states)}")

    # Check all tasks that exist in files
    for task_id, file_state in file_states.items():
        file_status = file_state['status']
        file_path = file_state['file_path']

        if task_id in api_states:
            api_state = api_states[task_id]
            api_status = api_state['status']
            api_raw_status = api_state['raw_status']

            debug(f"Comparing {task_id}: file={file_status}, api={api_status} (raw={api_raw_status})")

            if file_status != api_status:
                conflict = {
                    'task_id': task_id,
                    'file_status': file_status,
                    'api_status': api_status,
                    'api_raw_status': api_raw_status,
                    'file_path': file_path,
                    'resolution': 'use_file',
                }
                conflicts.append(conflict)

                warning(
                    f"Conflict detected for {task_id}: "
                    f"file={file_status}, api={api_raw_status}. "
                    f"Resolution: use file state."
                )
            else:
                debug(f"No conflict for {task_id}: states match ({file_status})")
        else:
            # Task exists in file but not in API - needs hydration, not a conflict
            debug(f"Task {task_id} exists in file but not in API (will be hydrated)")

    # Check for orphaned API tasks (exist in API but not in files)
    for task_id in api_states:
        if task_id not in file_states:
            warning(
                f"Orphaned API task detected: {task_id} exists in API but not in files. "
                f"This task will be ignored (file is authoritative)."
            )

    log(f"Conflict detection complete: {len(conflicts)} conflict(s) found")
    return conflicts


# ============================================================================
# Conflict Resolution
# ============================================================================

def resolve_conflicts(conflicts: list[dict]) -> dict:
    """
    Generate resolution actions for detected conflicts.

    Per the "file wins" policy, all conflicts are resolved by using file state.
    This function generates the data structure needed for re-hydration.

    Args:
        conflicts: List of conflict dictionaries from detect_conflicts().

    Returns:
        Resolution dictionary with:
            - conflicts_resolved: Number of conflicts resolved
            - actions: List of resolution actions for each conflict
            - rehydrate_tasks: List of task IDs that need re-hydration
    """
    resolution = {
        'conflicts_resolved': len(conflicts),
        'actions': [],
        'rehydrate_tasks': [],
    }

    for conflict in conflicts:
        task_id = conflict['task_id']
        file_status = conflict['file_status']
        api_status = conflict['api_status']

        action = {
            'task_id': task_id,
            'action': 'overwrite_api',
            'old_status': api_status,
            'new_status': file_status,
            'reason': f"File shows {file_status}, API shows {api_status}. File is authoritative.",
        }
        resolution['actions'].append(action)
        resolution['rehydrate_tasks'].append(task_id)

        log(f"Resolution action for {task_id}: overwrite API with file state ({file_status})")

    return resolution


def needs_rehydration(file_states: dict[str, dict], api_states: dict[str, dict]) -> bool:
    """
    Determine if re-hydration is needed based on state comparison.

    Re-hydration is needed when:
        1. Any conflicts exist (file and API disagree)
        2. Tasks exist in files but not in API (incomplete hydration)

    Args:
        file_states: Dictionary from get_file_states().
        api_states: Dictionary from parse_api_states().

    Returns:
        True if re-hydration is recommended, False otherwise.
    """
    # Check for conflicts
    conflicts = detect_conflicts(file_states, api_states)
    if conflicts:
        debug(f"Re-hydration needed: {len(conflicts)} conflict(s) detected")
        return True

    # Check for tasks in files but not in API
    for task_id in file_states:
        if task_id not in api_states:
            debug(f"Re-hydration needed: task {task_id} not in API")
            return True

    debug("No re-hydration needed: file and API states are consistent")
    return False


# ============================================================================
# Conflict Resolution Report
# ============================================================================

def generate_report(
    file_states: dict[str, dict],
    api_states: dict[str, dict],
    conflicts: list[dict],
    resolution: dict
) -> dict:
    """
    Generate a comprehensive conflict resolution report.

    Args:
        file_states: Dictionary from get_file_states().
        api_states: Dictionary from parse_api_states().
        conflicts: List of conflicts from detect_conflicts().
        resolution: Resolution dictionary from resolve_conflicts().

    Returns:
        Report dictionary suitable for JSON output.
    """
    report = {
        'timestamp': datetime.now().isoformat(),
        'summary': {
            'file_tasks_count': len(file_states),
            'api_tasks_count': len(api_states),
            'conflicts_found': len(conflicts),
            'conflicts_resolved': resolution.get('conflicts_resolved', 0),
            'rehydration_needed': needs_rehydration(file_states, api_states),
        },
        'conflicts': conflicts,
        'resolution': resolution,
        'debug_mode': is_debug_mode(),
    }

    # Add detailed state comparison in debug mode
    if is_debug_mode():
        report['debug'] = {
            'file_states': {
                task_id: state['status']
                for task_id, state in file_states.items()
            },
            'api_states': {
                task_id: state['status']
                for task_id, state in api_states.items()
            },
        }

    return report


# ============================================================================
# Integration Functions
# ============================================================================

def check_ticket_conflicts(
    ticket_path: str,
    api_tasks: Optional[list[dict]] = None
) -> dict:
    """
    Main entry point: Check for conflicts in a ticket.

    This function is designed to be called from hydrate-tasks.py or
    other integration points.

    Args:
        ticket_path: Path to ticket directory.
        api_tasks: Optional list of tasks from Tasks API. If None, assumes
                   no API tasks exist (initial hydration scenario).

    Returns:
        Conflict resolution report dictionary.
    """
    log(f"Checking conflicts for ticket: {ticket_path}")

    # Get file states
    file_states = get_file_states(ticket_path)
    if not file_states:
        debug("No task files found, no conflicts possible")
        return {
            'timestamp': datetime.now().isoformat(),
            'summary': {
                'file_tasks_count': 0,
                'api_tasks_count': 0,
                'conflicts_found': 0,
                'conflicts_resolved': 0,
                'rehydration_needed': False,
            },
            'conflicts': [],
            'resolution': {'conflicts_resolved': 0, 'actions': [], 'rehydrate_tasks': []},
        }

    # Parse API states
    api_states = parse_api_states(api_tasks or [])

    # Detect conflicts
    conflicts = detect_conflicts(file_states, api_states)

    # Resolve conflicts (generate resolution actions)
    resolution = resolve_conflicts(conflicts)

    # Generate report
    report = generate_report(file_states, api_states, conflicts, resolution)

    return report


def get_rehydration_data(
    ticket_path: str,
    api_tasks: Optional[list[dict]] = None
) -> dict:
    """
    Get data needed for re-hydration after conflict detection.

    Returns file states for tasks that need to be re-hydrated
    (either due to conflicts or missing from API).

    Args:
        ticket_path: Path to ticket directory.
        api_tasks: Optional list of tasks from Tasks API.

    Returns:
        Dictionary with:
            - needs_rehydration: bool
            - tasks_to_hydrate: List of task IDs that need hydration
            - task_states: Dict mapping task_id to file status
    """
    file_states = get_file_states(ticket_path)
    api_states = parse_api_states(api_tasks or [])

    # Detect conflicts
    conflicts = detect_conflicts(file_states, api_states)
    conflict_task_ids = {c['task_id'] for c in conflicts}

    # Find tasks missing from API
    missing_task_ids = {
        task_id for task_id in file_states
        if task_id not in api_states
    }

    # Combine: all tasks that need hydration
    tasks_to_hydrate = list(conflict_task_ids | missing_task_ids)
    tasks_to_hydrate.sort()

    # Get their states
    task_states = {
        task_id: file_states[task_id]['status']
        for task_id in tasks_to_hydrate
        if task_id in file_states
    }

    return {
        'needs_rehydration': len(tasks_to_hydrate) > 0,
        'tasks_to_hydrate': tasks_to_hydrate,
        'task_states': task_states,
        'conflicts_count': len(conflicts),
        'missing_count': len(missing_task_ids),
    }


# ============================================================================
# CLI Entry Point
# ============================================================================

def main() -> int:
    """
    CLI entry point for the conflict resolution module.

    Usage:
        python conflict-resolution.py <ticket_path> [api_tasks_json]

    Arguments:
        ticket_path: Path to the ticket directory
        api_tasks_json: Optional JSON string or file path with API tasks

    Returns:
        Exit code (0 for success, 1 for error).
    """
    if len(sys.argv) < 2:
        print("Usage: python conflict-resolution.py <ticket_path> [api_tasks_json]", file=sys.stderr)
        print("", file=sys.stderr)
        print("Arguments:", file=sys.stderr)
        print("  ticket_path     Path to the ticket directory", file=sys.stderr)
        print("  api_tasks_json  Optional JSON string or file path with API tasks", file=sys.stderr)
        print("", file=sys.stderr)
        print("Environment:", file=sys.stderr)
        print(f"  {DEBUG_ENV_VAR}=true  Enable debug mode for verbose logging", file=sys.stderr)
        return 1

    ticket_path = sys.argv[1]

    # Validate ticket path
    if not os.path.isdir(ticket_path):
        error(f"Ticket path does not exist: {ticket_path}")
        print(f"Error: Ticket path does not exist: {ticket_path}", file=sys.stderr)
        return 1

    tasks_dir = os.path.join(ticket_path, 'tasks')
    if not os.path.isdir(tasks_dir):
        error(f"Tasks directory does not exist: {tasks_dir}")
        print(f"Error: Tasks directory does not exist: {tasks_dir}", file=sys.stderr)
        return 1

    # Parse API tasks if provided
    api_tasks = None
    if len(sys.argv) > 2:
        api_tasks_arg = sys.argv[2]
        try:
            # Try as JSON string first
            api_tasks = json.loads(api_tasks_arg)
        except json.JSONDecodeError:
            # Try as file path
            if os.path.isfile(api_tasks_arg):
                try:
                    with open(api_tasks_arg, 'r', encoding='utf-8') as f:
                        api_tasks = json.load(f)
                except (json.JSONDecodeError, IOError) as e:
                    error(f"Failed to parse API tasks from file: {e}")
                    print(f"Error: Failed to parse API tasks from file: {e}", file=sys.stderr)
                    return 1
            else:
                error(f"Invalid API tasks argument: {api_tasks_arg}")
                print(f"Error: Invalid API tasks argument (not JSON or file path)", file=sys.stderr)
                return 1

    # Run conflict detection
    try:
        report = check_ticket_conflicts(ticket_path, api_tasks)
        print(json.dumps(report, indent=2))

        # Log summary
        summary = report.get('summary', {})
        conflicts_found = summary.get('conflicts_found', 0)
        if conflicts_found > 0:
            print(f"Detected {conflicts_found} conflict(s)", file=sys.stderr)
        else:
            print("No conflicts detected", file=sys.stderr)

        return 0

    except Exception as e:
        error(f"Error during conflict detection: {e}")
        print(f"Error during conflict detection: {e}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
