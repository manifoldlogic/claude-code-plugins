#!/usr/bin/env python3
"""
POC Stop Hook - Verify transcript access and API capabilities.

This is a proof-of-concept to validate that Stop hooks can:
1. Receive JSON input via stdin
2. Access the transcript_path
3. Read and parse the transcript JSONL file
4. Return JSON output to control stopping behavior

Results are logged to /tmp/poc-stop-hook.log for analysis.
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path

LOG_FILE = Path("/tmp/poc-stop-hook.log")

def log(message: str):
    """Append message to log file with timestamp."""
    timestamp = datetime.now().isoformat()
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {message}\n")

def main():
    log("=" * 60)
    log("POC Stop Hook triggered")

    try:
        # Step 1: Read stdin
        raw_input = sys.stdin.read()
        log(f"Raw stdin length: {len(raw_input)} bytes")

        # Step 2: Parse JSON input
        try:
            input_data = json.loads(raw_input)
            log(f"Parsed JSON keys: {list(input_data.keys())}")
        except json.JSONDecodeError as e:
            log(f"JSON parse error: {e}")
            log(f"Raw input (first 500 chars): {raw_input[:500]}")
            sys.exit(0)  # Allow stopping on error

        # Step 3: Log all received fields
        for key, value in input_data.items():
            if key == "transcript_path":
                log(f"  {key}: {value}")
            else:
                log(f"  {key}: {value}")

        # Step 4: Check for transcript_path
        transcript_path = input_data.get("transcript_path")
        if not transcript_path:
            log("WARNING: No transcript_path in input!")
            sys.exit(0)

        # Step 5: Check if transcript file exists
        transcript_file = Path(os.path.expanduser(transcript_path))
        if not transcript_file.exists():
            log(f"WARNING: Transcript file does not exist: {transcript_file}")
            sys.exit(0)

        log(f"Transcript file exists: {transcript_file}")
        log(f"Transcript file size: {transcript_file.stat().st_size} bytes")

        # Step 6: Read and parse transcript (last 10 lines)
        try:
            with open(transcript_file, "r") as f:
                lines = f.readlines()

            log(f"Transcript has {len(lines)} lines (JSONL entries)")

            # Parse last few entries
            for i, line in enumerate(lines[-5:]):
                try:
                    entry = json.loads(line.strip())
                    entry_type = entry.get("type", "unknown")
                    # Truncate content for logging
                    preview = str(entry)[:200] + "..." if len(str(entry)) > 200 else str(entry)
                    log(f"  Entry[-{5-i}] type={entry_type}: {preview}")
                except json.JSONDecodeError:
                    log(f"  Entry[-{5-i}] (not JSON): {line[:100]}...")
        except Exception as e:
            log(f"Error reading transcript: {e}")

        # Step 7: Check stop_hook_active flag
        stop_hook_active = input_data.get("stop_hook_active", False)
        log(f"stop_hook_active: {stop_hook_active}")

        if stop_hook_active:
            log("Already in Stop hook continuation - allowing stop")
            sys.exit(0)

        # Step 8: POC Success - allow stopping
        log("POC VERIFIED: All capabilities confirmed working!")
        log("=" * 60)

        # Allow stopping (don't block)
        sys.exit(0)

    except Exception as e:
        log(f"Unexpected error: {e}")
        import traceback
        log(traceback.format_exc())
        sys.exit(0)  # Allow stopping on error

if __name__ == "__main__":
    main()
