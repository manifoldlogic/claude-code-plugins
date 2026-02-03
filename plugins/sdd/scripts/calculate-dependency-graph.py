#!/usr/bin/env python3
"""
SDD Dependency Graph Calculator.

This module analyzes task files in a ticket directory and calculates:
1. Phase-based dependencies (Phase N depends on Phase N-1 completion)
2. Explicit dependencies (from ## Dependencies section in task files)
3. Independent tasks (tasks that can run in parallel within each phase)
4. Circular dependency detection (error condition)

The output is a JSON structure suitable for parallel execution scheduling.

Usage:
    # As a CLI tool
    python calculate-dependency-graph.py /path/to/ticket

    # As a module
    from calculate_dependency_graph import calculate_dependency_graph
    result = calculate_dependency_graph("/path/to/ticket")

Exit Codes:
    0: Success
    1: Error (invalid arguments, missing directory)
    2: Circular dependency detected

Output Format:
    {
      "phases": {"1": ["TASK.1001", "TASK.1002"], "2": ["TASK.2001"]},
      "dependencies": {"TASK.1001": [], "TASK.2001": ["TASK.1001", "TASK.1002"]},
      "independent": {"1": ["TASK.1001", "TASK.1002"], "2": ["TASK.2001"]}
    }
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

# Dependencies section pattern
DEPENDENCIES_SECTION_PATTERN = re.compile(
    r'^##\s+Dependencies\s*\n([\s\S]*?)(?=^##|\Z)',
    re.MULTILINE
)

# Dependency line pattern (e.g., "- TASKINT.1001" or "TASKINT.1001")
DEPENDENCY_LINE_PATTERN = re.compile(r'[A-Z]+\.\d{4}')

# Code block pattern (to skip parsing inside code blocks)
CODE_BLOCK_PATTERN = re.compile(r'```[\s\S]*?```', re.MULTILINE)


# ============================================================================
# Task File Parsing
# ============================================================================

def remove_code_blocks(content: str) -> str:
    """
    Remove code blocks from markdown content to avoid parsing dependencies in examples.

    Args:
        content: Markdown content that may contain code blocks.

    Returns:
        Content with code blocks replaced by empty strings.
    """
    return CODE_BLOCK_PATTERN.sub('', content)


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


def parse_explicit_dependencies(content: str) -> list[str]:
    """
    Extract explicit dependencies from the ## Dependencies section of a task file.

    Args:
        content: Full content of a task file.

    Returns:
        List of task IDs that this task explicitly depends on.
    """
    dependencies = []

    # Remove code blocks first
    clean_content = remove_code_blocks(content)

    # Find the Dependencies section
    section_match = DEPENDENCIES_SECTION_PATTERN.search(clean_content)
    if not section_match:
        return dependencies

    section_content = section_match.group(1)

    # Find all task ID references in the section
    for match in DEPENDENCY_LINE_PATTERN.finditer(section_content):
        dep_id = match.group(0)
        if dep_id not in dependencies:
            dependencies.append(dep_id)

    return dependencies


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
        explicit_deps = parse_explicit_dependencies(content)
        phase = get_phase_from_task_id(task_id)

        return {
            'task_id': task_id,
            'file_path': file_path,
            'explicit_dependencies': explicit_deps,
            'phase': phase,
        }

    except Exception as e:
        print(f"Warning: Could not parse task file {file_path}: {e}", file=sys.stderr)
        return None


# ============================================================================
# Task Discovery
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


# ============================================================================
# Phase Calculation
# ============================================================================

def calculate_phases(tasks: list[dict]) -> dict[str, list[str]]:
    """
    Group tasks by phase number.

    Args:
        tasks: List of task dictionaries with 'task_id' and 'phase' keys.

    Returns:
        Dictionary mapping phase number (as string) to list of task IDs.
    """
    phases: dict[str, list[str]] = {}

    for task in tasks:
        phase = task.get('phase')
        if phase is not None:
            phase_str = str(phase)
            if phase_str not in phases:
                phases[phase_str] = []
            phases[phase_str].append(task['task_id'])

    # Sort task IDs within each phase for deterministic output
    for phase_str in phases:
        phases[phase_str].sort()

    return phases


def calculate_phase_dependencies(tasks: list[dict], phases: dict[str, list[str]]) -> dict[str, list[str]]:
    """
    Calculate phase-based blocking relationships.

    Tasks in Phase N are blocked by all tasks in Phase N-1.
    Tasks in Phase 0 have no phase-based dependencies.

    Args:
        tasks: List of task dictionaries with 'task_id' and 'phase' keys.
        phases: Dictionary mapping phase number to task IDs.

    Returns:
        Dictionary mapping task_id to list of phase-based blocking task IDs.
    """
    phase_deps: dict[str, list[str]] = {}
    sorted_phases = sorted([int(p) for p in phases.keys()])

    for i, phase in enumerate(sorted_phases):
        phase_str = str(phase)

        # Get all tasks from previous phase
        prev_phase_tasks = []
        if i > 0:
            prev_phase = sorted_phases[i - 1]
            prev_phase_tasks = phases.get(str(prev_phase), [])

        # Each task in this phase is blocked by all previous phase tasks
        for task_id in phases[phase_str]:
            phase_deps[task_id] = prev_phase_tasks.copy()

    return phase_deps


# ============================================================================
# Full Dependency Calculation
# ============================================================================

def merge_dependencies(
    tasks: list[dict],
    phase_deps: dict[str, list[str]]
) -> dict[str, list[str]]:
    """
    Merge explicit dependencies with phase-based dependencies.

    Args:
        tasks: List of task dictionaries with explicit_dependencies.
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
        for dep in task.get('explicit_dependencies', []):
            if dep in all_task_ids:
                blockers.add(dep)

        # Sort for deterministic output
        merged[task_id] = sorted(list(blockers))

    return merged


# ============================================================================
# Independent Task Identification
# ============================================================================

def identify_independent_tasks(
    phases: dict[str, list[str]],
    all_deps: dict[str, list[str]]
) -> dict[str, list[str]]:
    """
    Identify tasks that can run in parallel within each phase.

    A task is independent within its phase if it has no explicit dependencies
    on other tasks in the same phase.

    Args:
        phases: Dictionary mapping phase number to task IDs.
        all_deps: Complete dependency mapping for all tasks.

    Returns:
        Dictionary mapping phase number to list of independent task IDs.
    """
    independent: dict[str, list[str]] = {}

    for phase_str, phase_tasks in phases.items():
        phase_task_set = set(phase_tasks)
        independent_in_phase = []

        for task_id in phase_tasks:
            deps = all_deps.get(task_id, [])
            # Check if any dependency is in the same phase
            same_phase_deps = [d for d in deps if d in phase_task_set]
            if not same_phase_deps:
                independent_in_phase.append(task_id)

        independent[phase_str] = sorted(independent_in_phase)

    return independent


# ============================================================================
# Circular Dependency Detection
# ============================================================================

def detect_circular_dependencies(all_deps: dict[str, list[str]]) -> Optional[list[str]]:
    """
    Detect circular dependencies using DFS-based cycle detection.

    Args:
        all_deps: Complete dependency mapping for all tasks.

    Returns:
        List of task IDs in the cycle if found, None otherwise.
    """
    # States: 0 = unvisited, 1 = visiting (in current path), 2 = visited
    state: dict[str, int] = {task_id: 0 for task_id in all_deps}
    path: list[str] = []

    def dfs(task_id: str) -> Optional[list[str]]:
        """
        Depth-first search for cycle detection.

        Returns the cycle path if found, None otherwise.
        """
        if state[task_id] == 1:
            # Found a cycle - return the path from this task back to itself
            cycle_start = path.index(task_id)
            return path[cycle_start:] + [task_id]

        if state[task_id] == 2:
            # Already fully processed
            return None

        # Mark as visiting
        state[task_id] = 1
        path.append(task_id)

        # Visit all dependencies
        for dep in all_deps.get(task_id, []):
            if dep in state:  # Only check deps that are in our task set
                cycle = dfs(dep)
                if cycle:
                    return cycle

        # Mark as visited
        state[task_id] = 2
        path.pop()

        return None

    # Run DFS from each unvisited node
    for task_id in all_deps:
        if state[task_id] == 0:
            cycle = dfs(task_id)
            if cycle:
                return cycle

    return None


# ============================================================================
# Main Calculation Function
# ============================================================================

def calculate_dependency_graph(ticket_path: str) -> dict:
    """
    Calculate the complete dependency graph for a ticket.

    This is the main entry point for the dependency graph calculator.

    Args:
        ticket_path: Path to ticket directory (must contain tasks/ subdirectory).

    Returns:
        Dictionary with:
        - phases: task IDs grouped by phase
        - dependencies: complete dependency mapping
        - independent: tasks that can run in parallel per phase

    Raises:
        ValueError: If circular dependency detected.
        FileNotFoundError: If ticket path doesn't exist.
    """
    tasks_dir = os.path.join(ticket_path, 'tasks')

    if not os.path.isdir(ticket_path):
        raise FileNotFoundError(f"Ticket path does not exist: {ticket_path}")

    if not os.path.isdir(tasks_dir):
        # No tasks directory - return empty graph
        return {
            'phases': {},
            'dependencies': {},
            'independent': {}
        }

    # Discover task files
    task_files = discover_task_files(tasks_dir)
    if not task_files:
        return {
            'phases': {},
            'dependencies': {},
            'independent': {}
        }

    # Parse each task file
    parsed_tasks = []
    for task_id, file_path in task_files:
        task_info = parse_task_file(task_id, file_path)
        if task_info:
            parsed_tasks.append(task_info)

    if not parsed_tasks:
        return {
            'phases': {},
            'dependencies': {},
            'independent': {}
        }

    # Calculate phases
    phases = calculate_phases(parsed_tasks)

    # Calculate phase-based dependencies
    phase_deps = calculate_phase_dependencies(parsed_tasks, phases)

    # Merge with explicit dependencies
    all_deps = merge_dependencies(parsed_tasks, phase_deps)

    # Detect circular dependencies
    cycle = detect_circular_dependencies(all_deps)
    if cycle:
        cycle_str = " -> ".join(cycle)
        raise ValueError(f"Circular dependency detected: {cycle_str}")

    # Identify independent tasks
    independent = identify_independent_tasks(phases, all_deps)

    return {
        'phases': phases,
        'dependencies': all_deps,
        'independent': independent
    }


# ============================================================================
# CLI Entry Point
# ============================================================================

def main() -> int:
    """
    CLI entry point for the dependency graph calculator.

    Usage:
        python calculate-dependency-graph.py <ticket_path>

    Returns:
        Exit code (0 for success, 1 for error, 2 for circular dependency).
    """
    if len(sys.argv) < 2:
        print("Usage: python calculate-dependency-graph.py <ticket_path>", file=sys.stderr)
        print("", file=sys.stderr)
        print("Arguments:", file=sys.stderr)
        print("  ticket_path   Path to the ticket directory", file=sys.stderr)
        return 1

    ticket_path = sys.argv[1]

    try:
        result = calculate_dependency_graph(ticket_path)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    except ValueError as e:
        # Circular dependency detected
        print(f"Error: {e}", file=sys.stderr)
        return 2

    except Exception as e:
        print(f"Error during dependency calculation: {e}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
