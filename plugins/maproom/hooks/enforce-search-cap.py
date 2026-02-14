#!/usr/bin/env python3
"""
PreToolUse hook: Enforce 5-search cap for maproom-researcher agent.

Tracks invocations of `crewchief-maproom search` and `crewchief-maproom vector-search`
per session. Blocks execution after the 5th search call (defense-in-depth enforcement
of the prompt-level constraint).

Hook behavior:
- Only activates for the maproom-researcher agent (checks CLAUDE_AGENT_NAME)
- Only intercepts Bash tool calls containing maproom search commands
- Uses a temp file counter to persist state across tool invocations
- Exit code 0 = allow, exit code 2 = block

Counter file: /tmp/maproom-search-count-{session_id}
  - session_id derived from CLAUDE_SESSION_ID or parent PID
  - File contains a single integer (current search count)
  - Automatically created on first search; missing file = count of 0
"""
import json
import os
import re
import sys
import tempfile

MAX_SEARCHES = 5
AGENT_NAME = "maproom-researcher"


def get_counter_file():
    """Return path to the session-scoped counter file."""
    # Use CLAUDE_SESSION_ID if available, fall back to parent PID
    session_id = os.environ.get("CLAUDE_SESSION_ID", str(os.getppid()))
    return os.path.join(tempfile.gettempdir(), f"maproom-search-count-{session_id}")


def read_count(counter_path):
    """Read the current search count from the counter file. Returns 0 if missing."""
    try:
        with open(counter_path, "r") as f:
            return int(f.read().strip())
    except (FileNotFoundError, ValueError):
        return 0


def write_count(counter_path, count):
    """Write the updated search count to the counter file."""
    with open(counter_path, "w") as f:
        f.write(str(count))


def is_maproom_search(command):
    """Check if a Bash command contains a maproom search or vector-search call."""
    return bool(re.search(r"crewchief-maproom\s+(search|vector-search)", command))


def main():
    try:
        # Only enforce for the maproom-researcher agent
        agent_name = os.environ.get("CLAUDE_AGENT_NAME", "")
        if agent_name != AGENT_NAME:
            sys.exit(0)

        # Read hook input from stdin
        input_data = json.load(sys.stdin)
        tool_name = input_data.get("tool_name", "")

        # Only intercept Bash tool calls
        if tool_name != "Bash":
            sys.exit(0)

        # Extract the command from tool input
        command = input_data.get("tool_input", {}).get("command", "")

        # Only count maproom search commands
        if not is_maproom_search(command):
            sys.exit(0)

        # Read current count, increment, and check cap
        counter_path = get_counter_file()
        count = read_count(counter_path)
        count += 1

        if count > MAX_SEARCHES:
            msg = (
                f"Search cap exceeded: {count - 1}/{MAX_SEARCHES} searches used. "
                f"Cannot execute additional searches.\n"
                f"The maproom-researcher agent is limited to {MAX_SEARCHES} search "
                f"invocations per session. Synthesize findings from existing results."
            )
            print(msg, file=sys.stderr)
            sys.exit(2)  # Block

        # Under cap: persist updated count and allow
        write_count(counter_path, count)
        sys.exit(0)

    except Exception as e:
        # On hook error, log warning but allow execution to continue
        # (fail-open to avoid breaking agent workflows)
        sys.stderr.write(f"Warning: maproom search cap hook error: {e}\n")
        sys.exit(0)


if __name__ == "__main__":
    main()
