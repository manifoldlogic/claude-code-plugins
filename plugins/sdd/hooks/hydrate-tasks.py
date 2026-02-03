#!/usr/bin/env python3
"""
SDD Task Hydration Module.

This module populates Claude Code's Tasks API from task markdown files,
enabling the hybrid file+API architecture for task management.

The hydration process:
1. Scans task files in {ticket_path}/tasks/*.md
2. Parses status checkboxes to determine task state
3. Extracts dependencies from ## Dependencies section
4. Outputs TaskCreate JSON commands for each task
5. Sets up blockedBy relationships for phase dependencies

Usage:
    # As a module
    from hydrate_tasks import hydrate_tasks_from_files
    task_ids = hydrate_tasks_from_files("/path/to/ticket", "TICKET-123")

    # As a CLI tool (outputs JSON commands)
    python hydrate-tasks.py /path/to/ticket TICKET-123

Exit Codes:
    0: Success
    1: Error (invalid arguments, etc.)

Output Format:
    JSON array of task creation commands suitable for processing.
"""

import json
import os
import re
import sys
from pathlib import Path
from typing import Optional


# ============================================================================
# Constants and Patterns
# ============================================================================

# Task ID pattern (e.g., TASKINT.1001, AUTH.2003)
TASK_ID_PATTERN = re.compile(r'^([A-Z]+)\.(\d{4})')

# Task ID in filename (e.g., TASKINT.1001_hydration-module.md)
TASK_FILENAME_PATTERN = re.compile(r'^([A-Z]+\.\d{4})_.*\.md$')

# Status checkbox patterns
# Match: - [ ] **Task completed** or - [x] **Task completed** (with optional bold)
TASK_COMPLETED_PATTERN = re.compile(
    r'^[\s]*-\s*\[([xX\s])\]\s*\*{0,2}Task completed\*{0,2}',
    re.MULTILINE
)

# Code block pattern (to skip parsing inside code blocks)
CODE_BLOCK_PATTERN = re.compile(r'```[\s\S]*?```', re.MULTILINE)

# Dependencies section pattern
DEPENDENCIES_SECTION_PATTERN = re.compile(
    r'^##\s+Dependencies\s*\n([\s\S]*?)(?=^##|\Z)',
    re.MULTILINE
)

# Dependency line pattern (e.g., "- TASKINT.1001" or "TASKINT.1001")
DEPENDENCY_LINE_PATTERN = re.compile(r'[A-Z]+\.\d{4}')


# ============================================================================
# Task File Parsing
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


def parse_task_status(content: str) -> str:
    """
    Parse the Task completed checkbox from task file content.

    Args:
        content: Full content of a task file.

    Returns:
        Status string: 'pending', 'completed', or 'pending' (default).
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


def parse_dependencies(content: str) -> list[str]:
    """
    Extract dependencies from the ## Dependencies section of a task file.

    Args:
        content: Full content of a task file.

    Returns:
        List of task IDs that this task depends on.
    """
    dependencies = []

    # Find the Dependencies section
    section_match = DEPENDENCIES_SECTION_PATTERN.search(content)
    if not section_match:
        return dependencies

    section_content = section_match.group(1)

    # Find all task ID references in the section
    for match in DEPENDENCY_LINE_PATTERN.finditer(section_content):
        dep_id = match.group(0)
        if dep_id not in dependencies:
            dependencies.append(dep_id)

    return dependencies


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


def get_phase_from_task_id(task_id: str) -> Optional[int]:
    """
    Extract phase number from task ID.

    Task IDs use the format TICKETID.XNNN where X indicates phase:
    - TASKINT.0001 -> Phase 0
    - TASKINT.1001 -> Phase 1
    - TASKINT.2001 -> Phase 2

    Args:
        task_id: Task ID string (e.g., "TASKINT.1001").

    Returns:
        Phase number (0-9), or None if invalid format.
    """
    match = TASK_ID_PATTERN.match(task_id)
    if not match:
        return None

    task_num = match.group(2)  # e.g., "1001"
    if len(task_num) == 4:
        return int(task_num[0])  # First digit is phase

    return None


def extract_subject_from_title(content: str, task_id: str) -> str:
    """
    Extract task subject from the title line.

    Expected format: # Task: [TASKINT.1001]: Task Hydration Module Implementation

    Args:
        content: Full content of a task file.
        task_id: Task ID for fallback subject.

    Returns:
        Task subject string.
    """
    # Look for title pattern
    title_pattern = re.compile(rf'^#\s+Task:\s*\[{re.escape(task_id)}\]:\s*(.+)$', re.MULTILINE)
    match = title_pattern.search(content)
    if match:
        return match.group(1).strip()

    # Fallback: use task ID
    return f"Task {task_id}"


def extract_summary(content: str) -> Optional[str]:
    """
    Extract the Summary section from task file content.

    Args:
        content: Full content of a task file.

    Returns:
        Summary text, or None if not found.
    """
    summary_pattern = re.compile(
        r'^##\s+Summary\s*\n([\s\S]*?)(?=^##|\Z)',
        re.MULTILINE
    )
    match = summary_pattern.search(content)
    if match:
        summary = match.group(1).strip()
        # Limit to first paragraph
        paragraphs = summary.split('\n\n')
        if paragraphs:
            return paragraphs[0].strip()
    return None


# ============================================================================
# Task Discovery and Parsing
# ============================================================================

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

            # Skip index files (e.g., TASKINT_TASK_INDEX.md)
            # Only skip if "INDEX" appears after an underscore (index suffix pattern)
            if '_INDEX' in filename.upper() or filename.upper().endswith('_INDEX.MD'):
                continue

            # Extract task ID
            task_id = extract_task_id_from_filename(filename)
            if not task_id:
                continue

            file_path = os.path.join(tasks_dir, filename)
            tasks.append((task_id, file_path))

    except OSError:
        pass

    # Sort by task ID for deterministic ordering
    tasks.sort(key=lambda x: x[0])
    return tasks


def parse_task_file(task_id: str, file_path: str) -> Optional[dict]:
    """
    Parse a task file and extract task information.

    Args:
        task_id: Task ID.
        file_path: Path to the task file.

    Returns:
        Dictionary with task information, or None if parsing fails.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except (OSError, IOError) as e:
        print(f"Warning: Could not read task file {file_path}: {e}", file=sys.stderr)
        return None

    try:
        status = parse_task_status(content)
        dependencies = parse_dependencies(content)
        subject = extract_subject_from_title(content, task_id)
        summary = extract_summary(content)
        phase = get_phase_from_task_id(task_id)

        return {
            'task_id': task_id,
            'file_path': file_path,
            'status': status,
            'dependencies': dependencies,
            'subject': subject,
            'description': summary or subject,
            'phase': phase,
        }

    except Exception as e:
        print(f"Warning: Could not parse task file {file_path}: {e}", file=sys.stderr)
        return None


# ============================================================================
# Phase Dependency Calculation
# ============================================================================

def calculate_phase_dependencies(tasks: list[dict]) -> dict[str, list[str]]:
    """
    Calculate phase-based blocking relationships.

    Tasks in Phase N are blocked by all tasks in Phase N-1.
    Tasks in Phase 0 have no phase-based dependencies.

    Args:
        tasks: List of task dictionaries with 'task_id' and 'phase' keys.

    Returns:
        Dictionary mapping task_id to list of blocking task IDs (phase-based only).
    """
    # Group tasks by phase
    phases: dict[int, list[str]] = {}
    for task in tasks:
        phase = task.get('phase')
        if phase is not None:
            if phase not in phases:
                phases[phase] = []
            phases[phase].append(task['task_id'])

    # Calculate phase dependencies
    phase_deps: dict[str, list[str]] = {}
    sorted_phases = sorted(phases.keys())

    for i, phase in enumerate(sorted_phases):
        # Get all tasks from previous phase
        prev_phase_tasks = []
        if i > 0:
            prev_phase = sorted_phases[i - 1]
            prev_phase_tasks = phases.get(prev_phase, [])

        # Each task in this phase is blocked by all previous phase tasks
        for task_id in phases[phase]:
            phase_deps[task_id] = prev_phase_tasks.copy()

    return phase_deps


def merge_dependencies(tasks: list[dict], phase_deps: dict[str, list[str]]) -> dict[str, list[str]]:
    """
    Merge explicit dependencies with phase-based dependencies.

    Args:
        tasks: List of task dictionaries with dependencies.
        phase_deps: Phase-based dependencies from calculate_phase_dependencies.

    Returns:
        Dictionary mapping task_id to complete list of blocking task IDs.
    """
    all_task_ids = {task['task_id'] for task in tasks}
    merged: dict[str, list[str]] = {}

    for task in tasks:
        task_id = task['task_id']
        blockers = set()

        # Add phase dependencies
        for dep in phase_deps.get(task_id, []):
            if dep in all_task_ids:
                blockers.add(dep)

        # Add explicit dependencies (but only if they're valid task IDs in this ticket)
        for dep in task.get('dependencies', []):
            if dep in all_task_ids:
                blockers.add(dep)

        # Sort for deterministic output
        merged[task_id] = sorted(list(blockers))

    return merged


# ============================================================================
# Task API Command Generation
# ============================================================================

def generate_task_commands(tasks: list[dict], all_deps: dict[str, list[str]], task_list_id: str) -> list[dict]:
    """
    Generate TaskCreate commands for each task.

    Args:
        tasks: List of parsed task dictionaries.
        all_deps: Merged dependencies for each task.
        task_list_id: The CLAUDE_TASK_LIST_ID value.

    Returns:
        List of TaskCreate command dictionaries.
    """
    commands = []

    for task in tasks:
        task_id = task['task_id']
        blocked_by = all_deps.get(task_id, [])

        # Generate activeForm from subject (present continuous)
        subject = task['subject']
        active_form = generate_active_form(subject)

        command = {
            'action': 'TaskCreate',
            'task_list_id': task_list_id,
            'task_id': task_id,
            'subject': subject,
            'description': task['description'],
            'status': task['status'],
            'activeForm': active_form,
            'blockedBy': blocked_by,
            'metadata': {
                'file_path': task['file_path'],
                'phase': task.get('phase'),
                'source': 'hydrate-tasks',
            }
        }

        commands.append(command)

    return commands


def generate_active_form(subject: str) -> str:
    """
    Generate present continuous form from imperative subject.

    For multi-word subjects where the first word is not a known verb,
    we prefix with "Working on:" to create a sensible active form.

    Examples:
        "Implement hydration module" -> "Implementing hydration module"
        "Create unit tests" -> "Creating unit tests"
        "Task Hydration Module" -> "Working on: Task Hydration Module"
        "API Verification" -> "Working on: API Verification"

    Args:
        subject: Task subject in imperative form.

    Returns:
        Subject in present continuous form.
    """
    # Simple heuristic: if first word looks like a verb, add -ing
    words = subject.split()
    if not words:
        return subject

    first_word = words[0].lower()

    # Handle common verb patterns
    transformations = {
        'implement': 'Implementing',
        'create': 'Creating',
        'update': 'Updating',
        'add': 'Adding',
        'fix': 'Fixing',
        'remove': 'Removing',
        'refactor': 'Refactoring',
        'test': 'Testing',
        'verify': 'Verifying',
        'review': 'Reviewing',
        'write': 'Writing',
        'build': 'Building',
        'configure': 'Configuring',
        'setup': 'Setting up',
        'integrate': 'Integrating',
        'migrate': 'Migrating',
        'document': 'Documenting',
        'delete': 'Deleting',
        'merge': 'Merging',
        'deploy': 'Deploying',
        'install': 'Installing',
        'enable': 'Enabling',
        'disable': 'Disabling',
        'run': 'Running',
        'execute': 'Executing',
        'analyze': 'Analyzing',
        'check': 'Checking',
        'validate': 'Validating',
        'define': 'Defining',
        'design': 'Designing',
        'establish': 'Establishing',
        'calculate': 'Calculating',
        'measure': 'Measuring',
        'benchmark': 'Benchmarking',
    }

    if first_word in transformations:
        words[0] = transformations[first_word]
        return ' '.join(words)

    # Check if first word looks like a common verb pattern
    # Verbs ending in common suffixes
    verb_endings = ('ate', 'ify', 'ize', 'ise')
    if first_word.endswith(verb_endings):
        # Handle -ate -> -ating, -ify -> -ifying, etc.
        if first_word.endswith('e'):
            words[0] = first_word[:-1] + 'ing'
        else:
            words[0] = first_word + 'ing'
        words[0] = words[0].capitalize()
        return ' '.join(words)

    # For any word NOT in our known verb list, use "Working on:" prefix
    # This is safer than trying to add -ing to nouns (e.g., "Tasking", "Performancing")
    return f"Working on: {subject}"


# ============================================================================
# Main Hydration Function
# ============================================================================

def hydrate_tasks_from_files(ticket_path: str, task_list_id: str) -> list[str]:
    """
    Create Tasks API entries from task markdown files.

    This is the main entry point for the hydration module.

    Args:
        ticket_path: Path to ticket directory (must contain tasks/ subdirectory).
        task_list_id: CLAUDE_TASK_LIST_ID value for task scoping.

    Returns:
        List of created task IDs in Tasks API order.
    """
    tasks_dir = os.path.join(ticket_path, 'tasks')

    # Discover task files
    task_files = discover_task_files(tasks_dir)
    if not task_files:
        return []

    # Parse each task file
    parsed_tasks = []
    for task_id, file_path in task_files:
        task_info = parse_task_file(task_id, file_path)
        if task_info:
            parsed_tasks.append(task_info)

    if not parsed_tasks:
        return []

    # Calculate phase dependencies
    phase_deps = calculate_phase_dependencies(parsed_tasks)

    # Merge with explicit dependencies
    all_deps = merge_dependencies(parsed_tasks, phase_deps)

    # Generate TaskCreate commands
    commands = generate_task_commands(parsed_tasks, all_deps, task_list_id)

    # Output commands as JSON (for processing by caller)
    print(json.dumps(commands, indent=2))

    # Return list of task IDs
    return [cmd['task_id'] for cmd in commands]


# ============================================================================
# CLI Entry Point
# ============================================================================

def main() -> int:
    """
    CLI entry point for the hydration module.

    Usage:
        python hydrate-tasks.py <ticket_path> <task_list_id>

    Returns:
        Exit code (0 for success, 1 for error).
    """
    if len(sys.argv) < 3:
        print("Usage: python hydrate-tasks.py <ticket_path> <task_list_id>", file=sys.stderr)
        print("", file=sys.stderr)
        print("Arguments:", file=sys.stderr)
        print("  ticket_path   Path to the ticket directory", file=sys.stderr)
        print("  task_list_id  CLAUDE_TASK_LIST_ID value", file=sys.stderr)
        return 1

    ticket_path = sys.argv[1]
    task_list_id = sys.argv[2]

    # Validate ticket path
    if not os.path.isdir(ticket_path):
        print(f"Error: Ticket path does not exist: {ticket_path}", file=sys.stderr)
        return 1

    tasks_dir = os.path.join(ticket_path, 'tasks')
    if not os.path.isdir(tasks_dir):
        print(f"Error: Tasks directory does not exist: {tasks_dir}", file=sys.stderr)
        return 1

    # Run hydration
    try:
        task_ids = hydrate_tasks_from_files(ticket_path, task_list_id)
        print(f"Hydrated {len(task_ids)} tasks", file=sys.stderr)
        return 0
    except Exception as e:
        print(f"Error during hydration: {e}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
