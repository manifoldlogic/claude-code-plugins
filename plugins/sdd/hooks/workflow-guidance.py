#!/usr/bin/env python3
"""
SDD Workflow Guidance Stop Hook.

This Stop hook provides SDD (Spec-Driven Development) workflow guidance by analyzing
the Claude session transcript when Claude finishes responding. It detects active
SDD workflows and suggests appropriate next steps.

Exit Codes:
    0: Allow stop (default, fail-safe)
    2: Block stop (with JSON output containing guidance)

MVP Behavior:
    Always exits 0 (allow stop), with guidance printed to stdout.
    Blocking behavior (exit 2) is reserved for future phases.

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
    and provides appropriate workflow guidance.

    Exit Codes:
        0: Allow stop (default behavior, fail-safe)
        2: Block stop (reserved for future use)
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
