#!/usr/bin/env python3
"""
SDD Workflow Guidance Stop Hook.

This Stop hook provides SDD (Spec-Driven Development) workflow guidance by analyzing
the Claude session transcript when Claude finishes responding. It detects active
SDD workflows and suggests appropriate next steps.

Exit Codes:
    0: Allow stop (default, fail-safe)
    2: Block stop (with JSON output containing gate block message or guidance)

Gate Enforcement:
    Before workflow guidance, checks for .autogate.json files in SDD_ROOT_DIR.
    If a gate blocks, exits 2 with gate message.
    Gate errors fail-safe to allow workflow guidance to proceed.

Input: JSON from stdin with fields:
    - session_id: Current session ID
    - transcript_path: Path to the JSONL transcript file
    - hook_event_name: Event name ("Stop")
    - stop_hook_active: Boolean, true if already in Stop hook continuation

Output: JSON to stdout (optional, for blocking):
    - decision: "block" or "allow"
    - reason: Guidance message for the user
"""

import json
import os
import re
import sys
from pathlib import Path
from typing import Optional

# ============================================================================
# Gate Configuration Types
# ============================================================================

# Default gate configuration (fail-safe: allow work to proceed)
DEFAULT_GATE_CONFIG = {'ready': True, 'stop_at_phase': None}


# ============================================================================
# Detection Patterns
# ============================================================================

# SDD command pattern (e.g., /sdd:plan-ticket, /sdd:do-task)
SDD_COMMAND_PATTERN = re.compile(r'/sdd:[a-z-]+')

# Ticket ID patterns
TICKET_ID_PATTERN = re.compile(r'\b[A-Z]+-\d+\b')  # e.g., AUTH-123, PROJ-42
TICKET_DIR_PATTERN = re.compile(r'\b[A-Z]+_[\w-]+\b')  # e.g., STOPHOOK_automation-replacement

# Task ID pattern (e.g., STOPHOOK.1001, AUTH.2003)
TASK_ID_PATTERN = re.compile(r'\b[A-Z]+\.\d{4}\b')

# Command categories for workflow state detection
# Planning commands - ordered by workflow progression
TICKET_INIT_COMMANDS = {'/sdd:plan-ticket', '/sdd:import-jira-ticket'}
REVIEW_COMMANDS = {'/sdd:review'}
UPDATE_COMMANDS = {'/sdd:update'}
TASK_CREATION_COMMANDS = {'/sdd:create-tasks'}
PLANNING_COMMANDS = TICKET_INIT_COMMANDS | REVIEW_COMMANDS | UPDATE_COMMANDS | TASK_CREATION_COMMANDS

IMPLEMENTATION_COMMANDS = {'/sdd:do-task', '/sdd:do-all-tasks'}
VERIFICATION_COMMANDS = {'/sdd:code-review', '/sdd:pr'}

# Minimum indicators required to trigger guidance (avoids false positives)
MIN_INDICATORS = 2

# Number of transcript lines to read
TRANSCRIPT_LINES = 50


# ============================================================================
# Input Parsing
# ============================================================================

def parse_input() -> dict:
    """
    Read and parse JSON input from stdin.

    Returns:
        Parsed JSON as a dictionary.

    Raises:
        json.JSONDecodeError: If stdin is not valid JSON.
        Exception: For any other error.
    """
    raw_input = sys.stdin.read()
    return json.loads(raw_input)


# ============================================================================
# Transcript Reading
# ============================================================================

def read_transcript_tail(path: str, num_lines: int = TRANSCRIPT_LINES) -> list[dict]:
    """
    Read the last N lines of a JSONL transcript file efficiently.

    Uses a backwards-reading approach for efficiency with large files:
    reads from the end of the file to avoid loading the entire file.

    Args:
        path: Path to the transcript JSONL file.
        num_lines: Number of lines to read from the end.

    Returns:
        List of parsed JSON entries (dictionaries).
        Returns empty list on any error.
    """
    transcript_path = Path(os.path.expanduser(path))

    if not transcript_path.exists():
        return []

    try:
        file_size = transcript_path.stat().st_size
        if file_size == 0:
            return []

        entries = []

        # For small files, just read all lines
        if file_size < 100_000:  # Less than 100KB
            with open(transcript_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()

            # Parse last N lines
            for line in lines[-num_lines:]:
                line = line.strip()
                if line:
                    try:
                        entry = json.loads(line)
                        entries.append(entry)
                    except json.JSONDecodeError:
                        continue
            return entries

        # For larger files, read backwards from end
        with open(transcript_path, 'rb') as f:
            # Start from end of file
            f.seek(0, 2)  # Seek to end
            position = f.tell()

            lines_found = 0
            buffer = b''
            chunk_size = 8192

            while position > 0 and lines_found < num_lines:
                # Read backwards in chunks
                read_size = min(chunk_size, position)
                position -= read_size
                f.seek(position)
                chunk = f.read(read_size)
                buffer = chunk + buffer

                # Count newlines in buffer
                lines_found = buffer.count(b'\n')

            # Decode and split into lines
            try:
                text = buffer.decode('utf-8')
            except UnicodeDecodeError:
                text = buffer.decode('utf-8', errors='replace')

            lines = text.strip().split('\n')

            # Parse last N lines
            for line in lines[-num_lines:]:
                line = line.strip()
                if line:
                    try:
                        entry = json.loads(line)
                        entries.append(entry)
                    except json.JSONDecodeError:
                        continue

        return entries

    except Exception:
        return []


# ============================================================================
# Gate Configuration Scanning and Evaluation
# ============================================================================

def scan_autogate_configs(sdd_root: str) -> dict:
    """
    Scan SDD_ROOT_DIR for .autogate.json files in tickets/ and epics/.

    Only scans the immediate subdirectories (one level deep) to find
    .autogate.json files for each ticket or epic.

    Args:
        sdd_root: Path to the SDD root directory (e.g., /workspace/.SDD).

    Returns:
        Dictionary mapping ticket/epic directory names to gate configs.
        Returns empty dict on any error.
    """
    gates = {}

    if not sdd_root or not os.path.isdir(sdd_root):
        return gates

    for subdir in ['tickets', 'epics']:
        dir_path = os.path.join(sdd_root, subdir)
        if not os.path.isdir(dir_path):
            continue

        try:
            for item_dir in os.listdir(dir_path):
                item_path = os.path.join(dir_path, item_dir)
                if not os.path.isdir(item_path):
                    continue

                config_path = os.path.join(item_path, '.autogate.json')
                if os.path.isfile(config_path):
                    try:
                        with open(config_path, 'r', encoding='utf-8') as f:
                            content = f.read()
                        config = parse_autogate_config(content)
                        gates[item_dir] = config
                    except Exception:
                        # Invalid config treated as no config (ready)
                        pass
        except Exception:
            # Directory listing error - skip this subdirectory
            continue

    return gates


def parse_autogate_config(content: str) -> dict:
    """
    Parse and validate .autogate.json content.

    Schema: {"ready": boolean, "stop_at_phase": int|null}

    Args:
        content: Raw JSON string from .autogate.json file.

    Returns:
        Dictionary with 'ready' (bool) and 'stop_at_phase' (int or None).
        Defaults: ready=True, stop_at_phase=None.
        Invalid JSON or values return defaults (fail-safe).
    """
    try:
        data = json.loads(content)

        # Extract and validate 'ready' field
        ready = data.get('ready', True)
        if not isinstance(ready, bool):
            ready = True

        # Extract and validate 'stop_at_phase' field
        stop_at_phase = data.get('stop_at_phase', None)
        if stop_at_phase is not None and not isinstance(stop_at_phase, int):
            stop_at_phase = None

        return {'ready': ready, 'stop_at_phase': stop_at_phase}

    except (json.JSONDecodeError, TypeError, AttributeError):
        # Invalid JSON treated as ready (fail-safe)
        return DEFAULT_GATE_CONFIG.copy()


def get_active_ticket_from_context(context: dict) -> Optional[str]:
    """
    Extract the active ticket directory name from SDD context.

    Uses the ticket_id from context, which is matched from TICKET_DIR_PATTERN
    (e.g., AUTOGATE_autonomous-work-gates) or TICKET_ID_PATTERN (e.g., AUTH-123).

    Args:
        context: Dictionary from detect_sdd_context().

    Returns:
        Ticket directory name if found, None otherwise.
    """
    return context.get('ticket_id')


def get_current_phase_number(context: dict) -> Optional[int]:
    """
    Map the planning_phase string to a numeric phase for gate comparison.

    Phase numbering:
        1 = 'init' or 'needs_review' (ticket created, needs review)
        2 = 'reviewed' (review complete)
        3 = 'tasks_created' (tasks generated)
        4 = implementation/verification (beyond planning)

    Args:
        context: Dictionary from detect_sdd_context().

    Returns:
        Phase number (1-4) or None if not in a workflow.
    """
    workflow = context.get('workflow', 'none')
    planning_phase = context.get('planning_phase')

    if workflow == 'none':
        return None

    if workflow == 'planning':
        phase_map = {
            'init': 1,
            'needs_review': 1,
            'reviewed': 2,
            'tasks_created': 3,
        }
        return phase_map.get(planning_phase, 1)

    if workflow == 'implementation':
        return 4

    if workflow == 'verification':
        return 4

    return None


def evaluate_gates(gates: dict, context: dict) -> dict:
    """
    Evaluate gates against the active work context.

    Checks:
        1. If active ticket has a gate with ready=false, block
        2. If active ticket has a gate with stop_at_phase=N and phase N is complete, block

    Args:
        gates: Dictionary from scan_autogate_configs().
        context: Dictionary from detect_sdd_context().

    Returns:
        Dictionary with:
            - blocked: bool (True if work should be blocked)
            - message: str (message explaining the block, empty if not blocked)
    """
    result = {'blocked': False, 'message': ''}

    active_ticket = get_active_ticket_from_context(context)
    if not active_ticket:
        return result

    # Check if active ticket has a gate configuration
    gate = gates.get(active_ticket)
    if not gate:
        return result

    # Check ready flag - if false, block all work on this ticket
    if not gate.get('ready', True):
        return {
            'blocked': True,
            'message': (
                f"AUTOGATE: Ticket {active_ticket} is gated (ready: false). "
                "Set ready: true in .autogate.json to continue autonomous work."
            )
        }

    # Check phase gate - if stop_at_phase is set and that phase is complete, block
    stop_at_phase = gate.get('stop_at_phase')
    if stop_at_phase is not None:
        current_phase = get_current_phase_number(context)
        if current_phase is not None and current_phase > stop_at_phase:
            return {
                'blocked': True,
                'message': (
                    f"AUTOGATE: Phase {stop_at_phase} complete for {active_ticket}. "
                    f"Currently at phase {current_phase}. "
                    "Review progress before proceeding to next phase, or update stop_at_phase in .autogate.json."
                )
            }

    return result


# ============================================================================
# Task File Inspection
# ============================================================================

# Regex patterns for checkbox parsing in task files
# Match: - [ ] **Task completed** or - [x] **Task completed** (with optional bold)
TASK_COMPLETED_PATTERN = re.compile(
    r'^[\s]*-\s*\[([xX\s])\]\s*\*{0,2}Task completed\*{0,2}',
    re.MULTILINE
)

# Match: - [ ] **Tests pass** or - [x] **Tests pass** (with optional bold)
TESTS_PASS_PATTERN = re.compile(
    r'^[\s]*-\s*\[([xX\s])\]\s*\*{0,2}Tests pass\*{0,2}',
    re.MULTILINE
)

# Match: - [ ] **Verified** or - [x] **Verified** (with optional bold)
VERIFIED_PATTERN = re.compile(
    r'^[\s]*-\s*\[([xX\s])\]\s*\*{0,2}Verified\*{0,2}',
    re.MULTILINE
)

# Pattern to detect code blocks (to skip checkbox parsing inside them)
CODE_BLOCK_PATTERN = re.compile(r'```[\s\S]*?```', re.MULTILINE)

# Pattern to extract task ID from filename (without word boundaries for start-of-string matching)
TASK_ID_FILENAME_PATTERN = re.compile(r'^([A-Z]+\.\d{4})')


def find_ticket_tasks_directory(sdd_root: str, ticket_id: str) -> Optional[str]:
    """
    Find the tasks directory for a given ticket.

    Handles both directory-style ticket IDs (AUTH_test-ticket) and
    Jira-style IDs (AUTH-123) by looking for matching directories.

    Args:
        sdd_root: Path to the SDD root directory.
        ticket_id: Ticket identifier (either AUTH-123 or AUTH_test-ticket format).

    Returns:
        Path to the tasks directory if found, None otherwise.
    """
    if not sdd_root or not ticket_id:
        return None

    tickets_dir = os.path.join(sdd_root, 'tickets')
    if not os.path.isdir(tickets_dir):
        return None

    try:
        # If ticket_id contains underscore, it's already in directory format
        if '_' in ticket_id:
            tasks_path = os.path.join(tickets_dir, ticket_id, 'tasks')
            if os.path.isdir(tasks_path):
                return tasks_path
            return None

        # Otherwise, look for directories starting with ticket_id
        # E.g., AUTH-123 might be in AUTH-123_feature-name/
        for item in os.listdir(tickets_dir):
            if item.startswith(ticket_id) or item.startswith(ticket_id.replace('-', '_')):
                tasks_path = os.path.join(tickets_dir, item, 'tasks')
                if os.path.isdir(tasks_path):
                    return tasks_path

        return None

    except Exception:
        return None


def remove_code_blocks(content: str) -> str:
    """
    Remove code blocks from markdown content to avoid parsing checkboxes in examples.

    Args:
        content: Markdown content that may contain code blocks.

    Returns:
        Content with code blocks replaced by empty strings.
    """
    return CODE_BLOCK_PATTERN.sub('', content)


def parse_task_file_status(content: str) -> dict:
    """
    Parse the Status section checkboxes from a task file.

    Extracts the state of three checkboxes:
    - Task completed: Whether the main task work is done
    - Tests pass: Whether tests have been run and passed
    - Verified: Whether the task has been verified

    Args:
        content: Full content of a task file.

    Returns:
        Dictionary with:
            - task_completed: bool (True if checkbox is checked)
            - tests_pass: bool (True if checkbox is checked)
            - verified: bool (True if checkbox is checked)
            - is_in_progress: bool (True if task_completed is unchecked)
    """
    result = {
        'task_completed': False,
        'tests_pass': False,
        'verified': False,
        'is_in_progress': False,
    }

    # Remove code blocks to avoid parsing example checkboxes
    clean_content = remove_code_blocks(content)

    # Parse Task completed checkbox
    match = TASK_COMPLETED_PATTERN.search(clean_content)
    if match:
        result['task_completed'] = match.group(1).lower() == 'x'

    # Parse Tests pass checkbox
    match = TESTS_PASS_PATTERN.search(clean_content)
    if match:
        result['tests_pass'] = match.group(1).lower() == 'x'

    # Parse Verified checkbox
    match = VERIFIED_PATTERN.search(clean_content)
    if match:
        result['verified'] = match.group(1).lower() == 'x'

    # Task is in progress if Task completed is unchecked
    # We detect this by: pattern was found AND it was unchecked
    if TASK_COMPLETED_PATTERN.search(clean_content):
        result['is_in_progress'] = not result['task_completed']

    return result


def extract_task_id_from_filename(filename: str) -> Optional[str]:
    """
    Extract task ID from a task filename.

    Expected format: TICKETID.NNNN_task-description.md
    E.g., STOPHOOK.1001_task-file-inspection.md -> STOPHOOK.1001

    Args:
        filename: Name of the task file.

    Returns:
        Task ID if found, None otherwise.
    """
    if not filename.endswith('.md'):
        return None

    # Match TICKETID.NNNN pattern at start of filename
    # Use TASK_ID_FILENAME_PATTERN which doesn't have word boundaries
    match = TASK_ID_FILENAME_PATTERN.match(filename)
    if match:
        return match.group(1)
    return None


def check_task_status(sdd_root: str, ticket_id: str) -> dict:
    """
    Check the completion status of tasks for a given ticket.

    Reads task files from the ticket's tasks/ directory and parses
    their Status section checkboxes to determine which tasks are
    in progress (have unchecked "Task completed" checkbox).

    **Multi-session limitation**: This check only detects tasks that
    were started but not completed. It cannot distinguish between
    tasks that were started in the current session vs. a previous
    session. Phase 2 will add session-scoped state to address this.

    Args:
        sdd_root: Path to the SDD root directory.
        ticket_id: Ticket identifier to check tasks for.

    Returns:
        Dictionary with:
            - has_in_progress: bool (True if any task is in progress)
            - in_progress_tasks: list of task IDs that are in progress
            - completed_tasks: list of task IDs that are completed
            - verified_tasks: list of task IDs that are verified
            - task_statuses: dict mapping task_id to status dict
            - error: str or None (error message if any)

    Note: All errors fail-safe (return has_in_progress=False).
    """
    result = {
        'has_in_progress': False,
        'in_progress_tasks': [],
        'completed_tasks': [],
        'verified_tasks': [],
        'task_statuses': {},
        'error': None,
    }

    try:
        # Find the tasks directory
        tasks_dir = find_ticket_tasks_directory(sdd_root, ticket_id)
        if not tasks_dir:
            # No tasks directory = no tasks = allow stop
            return result

        # Get list of task files
        try:
            task_files = [f for f in os.listdir(tasks_dir) if f.endswith('.md')]
        except Exception:
            # Can't list directory = fail-safe, allow stop
            return result

        if not task_files:
            # No task files = no tasks = allow stop
            return result

        # Parse each task file
        for task_file in task_files:
            task_id = extract_task_id_from_filename(task_file)
            if not task_id:
                continue

            task_path = os.path.join(tasks_dir, task_file)

            try:
                with open(task_path, 'r', encoding='utf-8') as f:
                    content = f.read()
            except Exception:
                # Can't read file = skip it, continue with others
                continue

            try:
                status = parse_task_file_status(content)
                result['task_statuses'][task_id] = status

                if status['verified']:
                    result['verified_tasks'].append(task_id)
                elif status['task_completed']:
                    result['completed_tasks'].append(task_id)
                elif status['is_in_progress']:
                    result['in_progress_tasks'].append(task_id)
                    result['has_in_progress'] = True

            except Exception:
                # Parse error = skip this task, continue with others
                continue

        return result

    except Exception as e:
        # Any unexpected error = fail-safe, allow stop
        result['error'] = str(e)
        return result


def generate_task_in_progress_message(context: dict, task_status: dict) -> str:
    """
    Generate a blocking message when tasks are in progress.

    Args:
        context: SDD context dictionary from detect_sdd_context().
        task_status: Dictionary from check_task_status().

    Returns:
        Human-readable message explaining what task is in progress.
    """
    ticket_id = context.get('ticket_id', 'unknown')
    in_progress = task_status.get('in_progress_tasks', [])

    if len(in_progress) == 1:
        task_id = in_progress[0]
        return (
            f"TASK IN PROGRESS: {task_id} has not been completed.\n\n"
            f"The task file shows 'Task completed' checkbox is unchecked.\n\n"
            f"Please complete the task by:\n"
            f"1. Finishing the implementation work\n"
            f"2. Running tests if applicable\n"
            f"3. Checking the 'Task completed' checkbox in the task file\n\n"
            f"If you need to abandon this task, check the 'Task completed' checkbox "
            f"and add a note explaining why.\n\n"
            f"Note: This detection has a known limitation in multi-session environments. "
            f"If this task was started in a different session, you can disable this check "
            f"by setting SDD_DISABLE_STOP_HOOK=1."
        )

    # Multiple tasks in progress
    task_list = ', '.join(in_progress)
    return (
        f"TASKS IN PROGRESS: {len(in_progress)} tasks are not completed: {task_list}\n\n"
        f"Each task file shows 'Task completed' checkbox is unchecked.\n\n"
        f"Please complete these tasks before switching context.\n\n"
        f"Note: This detection has a known limitation in multi-session environments. "
        f"If these tasks were started in different sessions, you can disable this check "
        f"by setting SDD_DISABLE_STOP_HOOK=1."
    )


# ============================================================================
# SDD Context Detection
# ============================================================================

def detect_sdd_context(entries: list[dict]) -> dict:
    """
    Detect SDD workflow context from transcript entries.

    Analyzes the transcript entries to determine the current workflow state
    by looking for SDD commands, ticket IDs, and task IDs in the 'display' field.

    Args:
        entries: List of transcript entries (dictionaries with 'display' field).

    Returns:
        Dictionary with:
            - workflow: "none" | "planning" | "implementation" | "verification"
            - planning_phase: "init" | "needs_review" | "reviewed" | "tasks_created" | None
            - indicators: List of detected indicator strings
            - task_id: Most recent task ID found, or None
            - ticket_id: Most recent ticket ID found, or None
            - has_review: Whether /sdd:review was run
            - has_update: Whether /sdd:update was run
            - has_create_tasks: Whether /sdd:create-tasks was run
    """
    result = {
        'workflow': 'none',
        'planning_phase': None,
        'indicators': [],
        'task_id': None,
        'ticket_id': None,
        'has_review': False,
        'has_update': False,
        'has_create_tasks': False,
    }

    if not entries:
        return result

    indicators = []
    sdd_commands_found = []
    task_ids_found = []
    ticket_ids_found = []

    for entry in entries:
        # Get the display text from the entry
        display = entry.get('display', '')
        if not display or not isinstance(display, str):
            continue

        # Check for SDD commands
        commands = SDD_COMMAND_PATTERN.findall(display)
        if commands:
            sdd_commands_found.extend(commands)
            indicators.extend(commands)

        # Check for task IDs
        tasks = TASK_ID_PATTERN.findall(display)
        if tasks:
            task_ids_found.extend(tasks)
            indicators.extend(tasks)

        # Check for ticket IDs (both patterns)
        tickets = TICKET_ID_PATTERN.findall(display)
        if tickets:
            ticket_ids_found.extend(tickets)
            indicators.extend(tickets)

        dir_tickets = TICKET_DIR_PATTERN.findall(display)
        if dir_tickets:
            ticket_ids_found.extend(dir_tickets)
            indicators.extend(dir_tickets)

    # Store unique indicators
    result['indicators'] = list(set(indicators))

    # Get most recent IDs (last found = most recent)
    if task_ids_found:
        result['task_id'] = task_ids_found[-1]
    if ticket_ids_found:
        result['ticket_id'] = ticket_ids_found[-1]

    # Track which planning commands have been run
    command_set = set(sdd_commands_found)
    result['has_review'] = bool(command_set.intersection(REVIEW_COMMANDS))
    result['has_update'] = bool(command_set.intersection(UPDATE_COMMANDS))
    result['has_create_tasks'] = bool(command_set.intersection(TASK_CREATION_COMMANDS))

    # Check if we have enough indicators to proceed
    if len(result['indicators']) < MIN_INDICATORS:
        return result

    # Determine workflow state based on commands and IDs
    workflow = determine_workflow_state(sdd_commands_found, task_ids_found, ticket_ids_found)
    result['workflow'] = workflow

    # Determine planning phase for more nuanced guidance
    if workflow == 'planning':
        result['planning_phase'] = determine_planning_phase(
            command_set,
            result['has_review'],
            result['has_update'],
            result['has_create_tasks']
        )

    return result


def determine_planning_phase(
    commands: set[str],
    has_review: bool,
    has_update: bool,
    has_create_tasks: bool
) -> str:
    """
    Determine the current phase within the planning workflow.

    Planning workflow progression:
        init -> needs_review -> reviewed -> tasks_created

    Args:
        commands: Set of SDD commands found.
        has_review: Whether /sdd:review was run.
        has_update: Whether /sdd:update was run.
        has_create_tasks: Whether /sdd:create-tasks was run.

    Returns:
        Planning phase: "init" | "needs_review" | "reviewed" | "tasks_created"
    """
    # If tasks have been created, we're in the final planning phase
    if has_create_tasks:
        return 'tasks_created'

    # If reviewed (and optionally updated), ready for task creation
    if has_review:
        return 'reviewed'

    # If ticket was initialized, needs review
    if commands.intersection(TICKET_INIT_COMMANDS):
        return 'needs_review'

    # Default to init phase
    return 'init'


def determine_workflow_state(
    commands: list[str],
    task_ids: list[str],
    ticket_ids: list[str]
) -> str:
    """
    Determine the workflow state based on detected indicators.

    Priority:
        1. If implementation commands or task IDs present -> "implementation"
        2. If verification commands present -> "verification"
        3. If planning commands or ticket IDs present -> "planning"
        4. Otherwise -> "none"

    Args:
        commands: List of SDD commands found.
        task_ids: List of task IDs found.
        ticket_ids: List of ticket IDs found.

    Returns:
        Workflow state string.
    """
    # Convert to sets for efficient lookup
    command_set = set(commands)

    # Check for implementation indicators (highest priority)
    if task_ids or command_set.intersection(IMPLEMENTATION_COMMANDS):
        return 'implementation'

    # Check for verification indicators
    if command_set.intersection(VERIFICATION_COMMANDS):
        return 'verification'

    # Check for planning indicators
    if ticket_ids or command_set.intersection(PLANNING_COMMANDS):
        return 'planning'

    return 'none'


# ============================================================================
# Guidance Generation
# ============================================================================

def generate_guidance(context: dict) -> Optional[str]:
    """
    Generate guidance message based on workflow context.

    Enforces review-first workflow:
        plan-ticket → review → update (if needed) → create-tasks → do-all-tasks

    Args:
        context: Dictionary from detect_sdd_context().

    Returns:
        Guidance message string, or None if no guidance needed.
    """
    workflow = context.get('workflow', 'none')

    if workflow == 'none':
        return None

    task_id = context.get('task_id')
    ticket_id = context.get('ticket_id')
    planning_phase = context.get('planning_phase')

    if workflow == 'planning':
        return _generate_planning_guidance(ticket_id, planning_phase)

    if workflow == 'implementation':
        if task_id:
            return (
                f"You're implementing task {task_id}. "
                "Consider running tests to verify the implementation, "
                "then commit your changes when ready."
            )
        return (
            "You're in an implementation workflow. "
            "Consider running tests to verify the implementation, "
            "then commit your changes when ready."
        )

    if workflow == 'verification':
        return (
            "Verification is in progress. Consider checking test results "
            "and committing verified changes. Use /sdd:pr to create a pull request."
        )

    return None


def _generate_planning_guidance(ticket_id: Optional[str], planning_phase: Optional[str]) -> str:
    """
    Generate guidance for planning workflow, enforcing review cycles.

    Workflow progression:
        needs_review → reviewed → tasks_created → ready for implementation

    Args:
        ticket_id: The ticket ID if found.
        planning_phase: Current planning phase.

    Returns:
        Guidance message string.
    """
    ticket_str = f" for {ticket_id}" if ticket_id else ""
    ticket_arg = f" {ticket_id}" if ticket_id else ""

    if planning_phase == 'needs_review':
        # Just created ticket - must review before creating tasks
        return (
            f"In planning workflow{ticket_str}: ticket created. "
            f"Run /sdd:review{ticket_arg} to validate the plan before creating tasks. "
            "Review identifies issues early and improves implementation quality."
        )

    if planning_phase == 'reviewed':
        # Reviewed - suggest update if needed, otherwise create tasks
        return (
            f"In planning workflow{ticket_str}: review complete. "
            f"If the review found issues, run /sdd:update{ticket_arg} to address them. "
            f"If the review passed, run /sdd:create-tasks{ticket_arg} to generate implementation tasks."
        )

    if planning_phase == 'tasks_created':
        # Tasks created - now ready for implementation
        return (
            f"In planning workflow{ticket_str}: tasks created. "
            f"Run /sdd:do-all-tasks{ticket_arg} to execute all tasks systematically, "
            f"or /sdd:do-task TASK_ID to work on a specific task."
        )

    # Default: init phase or unknown - guide toward review
    return (
        f"In planning workflow{ticket_str}. "
        f"Run /sdd:review{ticket_arg} to validate the plan and identify any issues. "
        "Review cycles improve confidence before task creation."
    )


# ============================================================================
# Output Helpers
# ============================================================================

def output_and_exit(decision: str, reason: Optional[str], exit_code: int) -> None:
    """
    Output JSON result and exit with specified code.

    Args:
        decision: "allow" or "block"
        reason: Guidance message, or None
        exit_code: Exit code (0 for allow, 2 for block)
    """
    if reason:
        output = {
            'decision': decision,
            'reason': reason,
        }
        print(json.dumps(output))

    sys.exit(exit_code)


# ============================================================================
# Main Entry Point
# ============================================================================

def main() -> None:
    """
    Entry point for the Stop hook.

    Parses input, checks for active SDD context in the transcript,
    evaluates work gates, and provides appropriate workflow guidance.

    Exit Codes:
        0: Allow stop (default behavior, fail-safe)
        2: Block stop (gate blocks work or guidance requires attention)
    """
    try:
        # Check environment variable to disable hook
        if os.environ.get('SDD_DISABLE_STOP_HOOK'):
            sys.exit(0)

        # Parse input from stdin
        try:
            input_data = parse_input()
        except (json.JSONDecodeError, Exception):
            # Invalid input - fail-safe, allow stop
            sys.exit(0)

        # CRITICAL: Check stop_hook_active FIRST to prevent infinite loops
        # This must be the first check after parsing input
        if input_data.get('stop_hook_active', False):
            sys.exit(0)

        # Get transcript path
        transcript_path = input_data.get('transcript_path')
        if not transcript_path:
            sys.exit(0)

        # Read recent transcript entries
        entries = read_transcript_tail(transcript_path)
        if not entries:
            sys.exit(0)

        # Detect SDD context
        context = detect_sdd_context(entries)

        # ====================================================================
        # Gate Enforcement (AUTOGATE)
        # Check work gates before providing workflow guidance.
        # Gate blocks result in exit 2 (early exit).
        # All gate errors fail-safe to continue with workflow guidance.
        # ====================================================================
        sdd_root = os.environ.get('SDD_ROOT_DIR', '')

        if not os.environ.get('AUTOGATE_BYPASS'):
            try:
                if sdd_root:
                    gates = scan_autogate_configs(sdd_root)
                    if gates:
                        gate_result = evaluate_gates(gates, context)
                        if gate_result.get('blocked', False):
                            output_and_exit('block', gate_result.get('message', ''), 2)
            except Exception:
                # Gate errors should not prevent workflow guidance
                # Fail-safe: continue to guidance below
                pass

        # ====================================================================
        # Task File Inspection
        # Check if any tasks are in progress (unchecked "Task completed").
        # Blocks with exit 2 if work is detected.
        # All errors fail-safe to allow stop (exit 0).
        #
        # Multi-session limitation: This check cannot distinguish between
        # tasks started in the current session vs. previous sessions.
        # Users can bypass with SDD_DISABLE_STOP_HOOK=1 if needed.
        # ====================================================================
        try:
            if sdd_root and context.get('ticket_id'):
                task_status = check_task_status(sdd_root, context['ticket_id'])
                if task_status.get('has_in_progress', False):
                    message = generate_task_in_progress_message(context, task_status)
                    output_and_exit('block', message, 2)
        except Exception:
            # Task inspection errors should not prevent workflow guidance
            # Fail-safe: continue to guidance below
            pass

        # Generate guidance based on context
        guidance = generate_guidance(context)

        # MVP: Always allow stop with optional guidance
        # Future phases may block on clear workflow violations
        if guidance:
            output_and_exit('allow', guidance, 0)
        else:
            sys.exit(0)

    except Exception:
        # Any error: fail-safe, allow stop
        sys.exit(0)


if __name__ == '__main__':
    main()
