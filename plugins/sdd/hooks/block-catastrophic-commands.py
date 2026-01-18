#!/usr/bin/env python3
"""
Block catastrophic system-level commands with irreversible harm.

Blocks only 3 categories of catastrophic operations:
- Root filesystem deletion (rm -rf /, rm -rf /*)
- Root permission compromise (chmod -R 777 /, chmod -R 777 /*)
- Disk wiping (dd to /dev/sd*)

This hook is intentionally minimal with hardcoded patterns to minimize
false positives. Commands with legitimate use cases (rm -rf /tmp/*,
sudo apt install) are NOT blocked.

Exit code 2 = blocking error (prevents execution)
Exit code 0 = allow execution
"""
import json
import sys
import re

# Hardcoded catastrophic patterns (no configuration)
# Patterns use (\s|$|[)`'"]) to catch:
#   - Direct commands: rm -rf /
#   - Command substitution: $(rm -rf /) or `rm -rf /`
#   - Quoted strings: "rm -rf /"
CATASTROPHIC_PATTERNS = [
    # Root filesystem deletion
    (r"\brm\s+-rf\s+/+(\s|$|[)`'\"])", "rm -rf / (root filesystem deletion)"),
    (r"\brm\s+-rf\s+/\*", "rm -rf /* (root filesystem deletion)"),
    # Root permission compromise
    (r"\bchmod\s+-R\s+777\s+/+(\s|$|[)`'\"])", "chmod -R 777 / (root permission compromise)"),
    (r"\bchmod\s+-R\s+777\s+/\*", "chmod -R 777 /* (root permission compromise)"),
    # Disk wiping
    (r"\bdd\b.*of=/dev/sd", "dd to block device (disk wipe)"),
]

def main():
    try:
        # Read hook input from stdin
        hook_input = json.load(sys.stdin)
        command = hook_input.get("tool_input", {}).get("command", "")

        # Check against catastrophic patterns
        for pattern, description in CATASTROPHIC_PATTERNS:
            if re.search(pattern, command):
                print(f"BLOCKED: Catastrophic command detected: {description}", file=sys.stderr)
                print(f"Command: {command}", file=sys.stderr)
                sys.exit(2)  # Block command

        sys.exit(0)  # Allow command

    except Exception as e:
        # On hook error, log but allow execution to continue
        sys.stderr.write(f"Warning: Catastrophic command filter error: {str(e)}\n")
        sys.exit(0)

if __name__ == "__main__":
    main()
