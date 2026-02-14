#!/usr/bin/env python3
"""
SessionEnd hook to clean up maproom search counter file.

Removes counter file from /tmp/ when session ends to reduce /tmp/ pollution.
Fails silently if file does not exist or cannot be removed.
"""
import os
import sys
import tempfile


def main():
    session_id = os.environ.get("CLAUDE_SESSION_ID", str(os.getppid()))
    # Sanitize session ID (defense in depth)
    session_id = session_id.replace('/', '_').replace('\\', '_')
    counter_file = os.path.join(tempfile.gettempdir(), f"maproom-search-count-{session_id}")

    try:
        if os.path.exists(counter_file):
            os.remove(counter_file)
    except Exception:
        # Best-effort cleanup - fail silently
        pass

    sys.exit(0)


if __name__ == "__main__":
    main()
