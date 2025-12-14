#!/usr/bin/env python3
"""
Block dangerous git commands that permanently delete uncommitted work.

Blocks:
- git reset --hard (permanently deletes uncommitted changes)
- git clean -fd (permanently deletes untracked files)
- git clean -fdx (permanently deletes untracked and ignored files)

This hook runs as a PreToolUse hook on the Bash tool.
Exit code 2 = blocking error (prevents execution)
Exit code 0 = allow execution
"""
import json
import sys
import re

def main():
    try:
        # Read hook input from stdin
        input_data = json.load(sys.stdin)
        command = input_data.get("tool_input", {}).get("command", "")

        # Define patterns for dangerous commands
        dangerous_patterns = [
            (r"\bgit\s+reset\s+--hard\b", "git reset --hard"),
            (r"\bgit\s+clean\s+-fd(?:x)?\b", "git clean -fd/fdx"),
        ]

        # Check if command matches any dangerous pattern
        for pattern, cmd_name in dangerous_patterns:
            if re.search(pattern, command):
                error_msg = f"""
❌ BLOCKED: Dangerous git command not allowed

Command: {command}
Blocked: {cmd_name}

This command permanently deletes uncommitted work with no recovery mechanism.

Safe alternatives:
  - Instead of 'git reset --hard': use 'git stash && git rebase origin/main && git stash pop'
  - Instead of 'git clean -fd': use 'git clean -fdn' (dry-run) then selective 'rm'

If you must run this command, execute it directly in your terminal.

This protection was added after MRMIGNR.2001 incident where 'git reset --hard'
destroyed completed implementation before commit.
"""
                sys.stderr.write(error_msg)
                # Exit code 2 = blocking error
                sys.exit(2)

        # Command is safe, allow execution
        sys.exit(0)

    except Exception as e:
        # On hook error, log but allow execution to continue
        sys.stderr.write(f"Warning: Git safety hook error: {str(e)}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
