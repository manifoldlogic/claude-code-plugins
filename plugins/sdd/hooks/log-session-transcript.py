#!/usr/bin/env python3
"""
Log session transcript metadata for later skill discovery analysis.

Handles both PreCompact and SessionEnd hook events by detecting the event type
from the hook_event_name field in the input JSON. Writes individual JSON metadata
files to ${SDD_ROOT_DIR}/logs/session-transcripts/ for each event.

PreCompact-specific fields: trigger, custom_instructions
SessionEnd-specific fields: reason

This hook is completely silent and exits 0 under ALL error conditions.
It never prints to stdout or stderr.

Exit code 0 = always (passive logging, never blocks)
"""
import json
import os
import re
import sys
import datetime

# Maximum length for sanitized session IDs to prevent filesystem issues
MAX_SESSION_ID_LENGTH = 128

# Known hook events this script handles
KNOWN_EVENTS = {"PreCompact", "SessionEnd"}


def sanitize_session_id(session_id):
    """
    Sanitize session ID for safe use in filenames.

    Removes path traversal characters and truncates to MAX_SESSION_ID_LENGTH
    to prevent filesystem issues from excessively long IDs.

    Defense-in-depth against path traversal:
    1. Strip dangerous characters: /, \\, .., null bytes
    2. Truncate to MAX_SESSION_ID_LENGTH chars to prevent filesystem issues
    3. Apply os.path.basename() as final layer

    Args:
        session_id: Raw session ID from hook input

    Returns:
        Sanitized session ID safe for filename use
    """
    sanitized = session_id.replace('/', '').replace('\\', '').replace('..', '').replace('\0', '')[:MAX_SESSION_ID_LENGTH]
    return os.path.basename(sanitized)


def sanitize_event_name(event_name):
    """
    Sanitize hook event name for safe use in filenames.

    Removes non-alphanumeric characters (except hyphen/underscore) and
    truncates to 20 characters to prevent filesystem issues.

    Args:
        event_name: Raw event name from hook input

    Returns:
        Sanitized event name safe for filename use
    """
    # Remove special characters, keep alphanumeric + hyphen + underscore
    sanitized = re.sub(r'[^a-zA-Z0-9_-]', '', event_name)
    return sanitized[:20].lower()


def main():
    try:
        # Read hook input from stdin
        input_data = json.load(sys.stdin)
    except Exception:
        # Cannot read stdin or malformed JSON -> exit 0 silently
        sys.exit(0)

    # Check for SDD_ROOT_DIR environment variable
    sdd_root = os.environ.get('SDD_ROOT_DIR', '')
    if not sdd_root:
        sys.exit(0)

    # Construct and create log directory
    log_dir = os.path.join(sdd_root, 'logs', 'session-transcripts')
    try:
        os.makedirs(log_dir, exist_ok=True)
    except Exception:
        # Cannot create log directory -> exit 0 silently
        sys.exit(0)

    # Extract common fields
    session_id = input_data.get('session_id', '')
    transcript_path = input_data.get('transcript_path', '')
    cwd = input_data.get('cwd', '')
    hook_event_name = input_data.get('hook_event_name', '')

    # Determine status based on transcript_path
    status = 'ok' if transcript_path else 'empty_path'

    # Capture current time once and derive both formats from the same instant
    now = datetime.datetime.now()
    compact_timestamp = now.strftime('%Y%m%dT%H%M%S%f')
    iso_timestamp = now.isoformat()

    # Build log entry with common fields
    log_entry = {
        'session_id': session_id,
        'transcript_path': transcript_path,
        'cwd': cwd,
        'hook_event_name': hook_event_name,
        'timestamp': iso_timestamp,
        'status': status,
    }

    # Add event-specific fields
    if hook_event_name == 'PreCompact':
        log_entry['trigger'] = input_data.get('trigger', '')
        log_entry['custom_instructions'] = input_data.get('custom_instructions', '')
    elif hook_event_name == 'SessionEnd':
        log_entry['reason'] = input_data.get('reason', '')

    # Check if event is recognized
    if hook_event_name not in KNOWN_EVENTS:
        log_entry['status'] = 'unknown_event'

    # Sanitize session_id for filename
    sanitized_session_id = sanitize_session_id(session_id) if session_id else 'unknown'

    # Construct filename with sanitized event name
    event = hook_event_name if hook_event_name else 'unknown'
    sanitized_event = sanitize_event_name(event)
    filename = f"{sanitized_session_id}_{sanitized_event}_{compact_timestamp}.json"
    filepath = os.path.join(log_dir, filename)

    # Set umask for 0600 file permissions before writing
    old_umask = os.umask(0o077)
    try:
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(log_entry, f, indent=2)
    except Exception:
        # Cannot write log file -> exit 0 silently
        pass
    finally:
        os.umask(old_umask)

    sys.exit(0)


if __name__ == '__main__':
    main()
