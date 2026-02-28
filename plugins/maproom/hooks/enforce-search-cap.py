#!/usr/bin/env python3
"""
PreToolUse hook: Enforce two-tier search cap for maproom-researcher agent.

Tracks invocations of `maproom search` and `maproom vector-search`
per session using a soft/hard cap threshold system:

  - Searches 1-5 (below soft cap): allowed silently (exit 0)
  - Searches 6-10 (soft cap to hard cap): allowed with stderr warning (exit 0)
  - Searches 11+ (above hard cap): blocked with stderr message (exit 2)

The soft cap warning is emitted on every search from 6 through 10, with a climbing
count (e.g., "7/10") so the agent can gauge proximity to the hard block.

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
import traceback

SOFT_CAP = 5
HARD_CAP = 10
AGENT_NAME = "maproom-researcher"
METRICS_ENABLED = os.environ.get("MAPROOM_METRICS_ENABLED") in ["1", "true", "yes"]


def emit_metric(metric_name, value=1):
    """Emit a metric to stderr for collection by monitoring systems.

    Metrics are only emitted if MAPROOM_METRICS_ENABLED is set.
    Format: METRIC:{metric_name}:{value}
    """
    if METRICS_ENABLED:
        sys.stderr.write(f"METRIC:{metric_name}:{value}\n")


def get_counter_file():
    """Return path to the session-scoped counter file."""
    # Use CLAUDE_SESSION_ID if available, fall back to parent PID
    session_id = os.environ.get("CLAUDE_SESSION_ID", str(os.getppid()))
    session_id = session_id.replace('/', '_').replace('\\', '_')
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
    return bool(re.search(r"maproom\s+(search|vector-search)", command))


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

        # Read current count, increment, and check thresholds
        counter_path = get_counter_file()
        count = read_count(counter_path)
        count += 1

        if count > HARD_CAP:
            # Hard cap exceeded: block without incrementing counter
            msg = (
                f"Search cap exceeded: {count - 1}/{HARD_CAP} searches used. "
                f"Cannot execute additional searches.\n"
                f"The maproom-researcher agent is limited to {HARD_CAP} search "
                f"invocations per session. Synthesize findings from existing results."
            )
            print(msg, file=sys.stderr)
            emit_metric("maproom.search_cap.hard_block")
            sys.exit(2)  # Block
        elif count > SOFT_CAP:
            # Soft cap reached: warn but allow, increment counter
            remaining = HARD_CAP - count
            msg = (
                f"Soft search cap reached: {count}/{HARD_CAP} searches used.\n"
                f"Start wrapping up Phase 1 -- you have {remaining} searches "
                f"remaining before the hard cap."
            )
            print(msg, file=sys.stderr)
            emit_metric("maproom.search_cap.soft_warning")
            write_count(counter_path, count)
            sys.exit(0)
        else:
            # Under soft cap: allow silently, increment counter
            write_count(counter_path, count)
            sys.exit(0)

    except Exception as e:
        # On hook error, log warning but allow execution to continue
        # (fail-open to avoid breaking agent workflows)
        sys.stderr.write(f"Warning: maproom search cap hook error: {e}\n")
        sys.stderr.write(traceback.format_exc())
        sys.exit(0)


if __name__ == "__main__":
    main()
