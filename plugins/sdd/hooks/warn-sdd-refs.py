#!/usr/bin/env python3
"""
Warn when .sdd directory references are added to production code files.

This hook detects hardcoded references to the .sdd planning directory in production
code, which creates environment-specific dependencies. The .sdd directory is for
planning and workflow management only.

Detected patterns:
- .sdd/ or .sdd\ (path references)
- SDD_ROOT_DIR (environment variable name)
- ${SDD_ROOT (shell variable expansion)
- /app/.sdd (default hardcoded path)

This hook runs as a PostToolUse hook on Edit and Write tools.
Exit code 0 = always (warning only, non-blocking)
"""
import json
import sys
import re
import os

def should_skip_file(file_path):
    """
    Determine if a file should be skipped from .sdd reference checking.

    Skip files:
    - Larger than 100KB (performance safeguard)
    - Inside .sdd directory (planning documents)
    - Inside plugins directory (Claude Code plugins - any /plugins/ path segment)
    - Inside .devcontainer directory (infrastructure configuration)
    - Documentation files (.md) - not production code
    - Config files (.json, .yaml, .yml) within plugins/ or .sdd/ directories
    - Shell scripts (.sh) within plugins/ directories
    """
    try:
        # Skip if file is too large (performance)
        if os.path.getsize(file_path) > 100 * 1024:  # 100KB
            return True
    except (OSError, FileNotFoundError):
        # If we can't get file size, skip to avoid errors
        return True

    # Normalize path for checking
    normalized = os.path.normpath(file_path)

    # Get file extension
    ext = os.path.splitext(file_path)[1].lower()

    # Skip ALL markdown files - they are documentation, not production code
    if ext == '.md':
        return True

    # Skip if in .sdd directory (any path containing /.sdd/)
    if '/.sdd/' in normalized or normalized.startswith('.sdd/') or '/.sdd' == normalized[-5:]:
        return True

    # Skip if in plugins directory (Claude Code plugins)
    # Check for /plugins/ anywhere in path to handle temp directories in tests
    if '/plugins/' in normalized or normalized.startswith('plugins/'):
        return True

    # Skip .devcontainer directory (infrastructure configuration)
    if '/.devcontainer/' in normalized or normalized.startswith('.devcontainer/'):
        return True

    # Skip config/script files within .sdd directories (already handled above)
    # This is kept for documentation but the .sdd check above covers it

    return False

def has_bypass_comment(file_path):
    """
    Check if file contains bypass comment: # sdd-ref-check: ignore
    """
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            return 'sdd-ref-check: ignore' in content
    except (OSError, FileNotFoundError):
        # If we can't read file, don't bypass (but we'll skip in main anyway)
        return False

def check_file_for_sdd_refs(file_path):
    """
    Check file for .sdd directory references.

    Returns tuple: (found, matches)
    - found: boolean indicating if patterns were found
    - matches: list of tuples (line_number, line_content, pattern_name)
    """
    # Define patterns with word boundaries to prevent false positives
    patterns = [
        (r'\.sdd(?=[/\\])', '.sdd/ path reference'),       # .sdd/ or .sdd\ (using lookahead for boundary)
        (r'\bSDD_ROOT_DIR\b', 'SDD_ROOT_DIR variable'),     # Environment variable name (word boundaries)
        (r'\$\{SDD_ROOT', '${SDD_ROOT variable expansion'), # Shell variable expansion
        (r'/app/\.sdd', '/app/.sdd hardcoded path'),       # Default hardcoded path
    ]

    matches = []

    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, start=1):
                for pattern, pattern_name in patterns:
                    if re.search(pattern, line):
                        matches.append((line_num, line.strip(), pattern_name))
    except (OSError, FileNotFoundError, UnicodeDecodeError):
        # If we can't read the file, return no matches
        return False, []

    return len(matches) > 0, matches

def log_warning(file_path, matches):
    """
    Optionally append warning to audit log file.
    """
    try:
        sdd_root = os.environ.get('SDD_ROOT_DIR', '/app/.sdd')
        log_file = os.path.join(sdd_root, 'logs', 'ref-warnings.log')

        # Create logs directory if it doesn't exist
        os.makedirs(os.path.dirname(log_file), exist_ok=True)

        with open(log_file, 'a', encoding='utf-8') as f:
            from datetime import datetime
            timestamp = datetime.now().isoformat()
            f.write(f"\n[{timestamp}] WARNING: .sdd reference detected in {file_path}\n")
            for line_num, line_content, pattern_name in matches:
                f.write(f"  Line {line_num}: {pattern_name}\n")
                f.write(f"    {line_content}\n")
    except Exception:
        # Logging is optional, don't fail if it doesn't work
        pass

def main():
    try:
        # Check for bypass environment variable (emergency disable)
        if os.environ.get('SDD_SKIP_REF_CHECK') == 'true':
            sys.exit(0)  # Skip all checks

        # Read hook input from stdin
        input_data = json.load(sys.stdin)

        # Get file path from tool_input
        tool_input = input_data.get("tool_input", {})
        file_path = tool_input.get("file_path", "")

        # If no file_path, nothing to check
        if not file_path:
            sys.exit(0)

        # Check if file should be skipped
        if should_skip_file(file_path):
            sys.exit(0)

        # Check if file has bypass comment
        if has_bypass_comment(file_path):
            sys.exit(0)

        # Check file for .sdd references
        found, matches = check_file_for_sdd_refs(file_path)

        if found:
            # Log warning to audit file (optional)
            log_warning(file_path, matches)

            # Emit warning to stderr
            warning_msg = f"""
⚠️  WARNING: .sdd directory reference detected in production code

File: {file_path}

Found references:
"""
            for line_num, line_content, pattern_name in matches:
                warning_msg += f"  Line {line_num}: {pattern_name}\n"
                warning_msg += f"    {line_content}\n"

            warning_msg += """
The .sdd directory is for planning and workflow management only.
Hardcoding .sdd paths in production code creates environment-specific dependencies.

Recommended solutions:
  - Remove hardcoded .sdd references from production code
  - Use configuration files or environment variables for paths
  - Keep .sdd references in plugin code, planning docs, or test fixtures only

To bypass this warning:
  - Add comment anywhere in file: # sdd-ref-check: ignore
  - Set environment variable: SDD_SKIP_REF_CHECK=true

This is a warning only. Your changes have been saved.
"""
            sys.stderr.write(warning_msg)

        # Always exit 0 (warning only, non-blocking)
        sys.exit(0)

    except Exception as e:
        # On hook error, log but don't block (warning only)
        sys.stderr.write(f"Warning: SDD ref check hook error: {str(e)}\n")
        sys.exit(0)

if __name__ == "__main__":
    main()
