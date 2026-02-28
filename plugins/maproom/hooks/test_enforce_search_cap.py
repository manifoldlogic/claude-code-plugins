#!/usr/bin/env python3
"""
Unit tests for enforce-search-cap.py hook.

Tests verify the two-tier search cap system for the maproom-researcher agent:
  - Searches 1-5 (below soft cap): allowed silently
  - Searches 6-10 (soft cap to hard cap): allowed with stderr warning
  - Searches 11+ (above hard cap): blocked

Covers threshold boundaries, bypass paths, error handling, counter state,
and filesystem error fail-open behavior.
"""
import glob
import json
import os
import stat
import subprocess
import tempfile
import unittest

# Path to the hook script
HOOK_PATH = os.path.join(os.path.dirname(__file__), "enforce-search-cap.py")

# Standard maproom search command used in most tests
MAPROOM_SEARCH_CMD = "maproom search 'test query'"


def run_hook(json_input, env_vars=None, session_id=None):
    """
    Run hook via subprocess with controlled inputs.

    Args:
        json_input: String to feed on stdin (raw string, not further serialized).
        env_vars: Dict of environment variables to set.
        session_id: If provided, sets CLAUDE_SESSION_ID in the environment.

    Returns:
        (exit_code, stdout, stderr) tuple.
    """
    env = os.environ.copy()
    # Default to maproom-researcher agent unless overridden
    env["CLAUDE_AGENT_NAME"] = "maproom-researcher"
    if env_vars:
        env.update(env_vars)
    if session_id is not None:
        env["CLAUDE_SESSION_ID"] = session_id

    result = subprocess.run(
        ["python3", HOOK_PATH],
        input=json_input,
        capture_output=True,
        text=True,
        env=env,
    )
    return result.returncode, result.stdout, result.stderr


def _counter_path(session_id):
    """Return the counter file path for a given session ID."""
    return f"/tmp/maproom-search-count-{session_id}"


def _seed_counter(session_id, value):
    """Pre-seed a counter file with a given integer value."""
    with open(_counter_path(session_id), "w") as f:
        f.write(str(value))


def _read_counter(session_id):
    """Read the counter file value for a given session ID."""
    try:
        with open(_counter_path(session_id), "r") as f:
            return int(f.read().strip())
    except (FileNotFoundError, ValueError):
        return None


def _make_search_input(command=None):
    """Build the standard JSON input for a Bash tool call."""
    if command is None:
        command = MAPROOM_SEARCH_CMD
    return json.dumps({
        "tool_name": "Bash",
        "tool_input": {"command": command},
    })


def teardown_module():
    """Remove test counter files after all tests complete."""
    for path in glob.glob("/tmp/maproom-search-count-test-*"):
        try:
            os.remove(path)
        except OSError:
            pass


# =============================================================================
# Threshold Boundary Tests (Critical Path)
# =============================================================================

class TestThresholdBoundaries:
    """Tests for soft cap and hard cap threshold boundaries."""

    def test_search_1_first_search(self):
        """First search (count 1): allowed silently, no cap-related output."""
        sid = "test-threshold-1"
        # Counter absent = count 0 before invocation
        exit_code, stdout, stderr = run_hook(_make_search_input(), session_id=sid)
        assert exit_code == 0
        assert "cap" not in stderr.lower()
        assert _read_counter(sid) == 1

    def test_search_5_at_soft_cap(self):
        """Search 5 (at soft cap boundary): allowed silently, no warning."""
        sid = "test-threshold-5"
        _seed_counter(sid, 4)
        exit_code, stdout, stderr = run_hook(_make_search_input(), session_id=sid)
        assert exit_code == 0
        assert "cap" not in stderr.lower()
        assert _read_counter(sid) == 5

    def test_search_6_first_warning(self):
        """Search 6 (first warning): allowed with soft cap warning showing 6/10."""
        sid = "test-threshold-6"
        _seed_counter(sid, 5)
        exit_code, stdout, stderr = run_hook(_make_search_input(), session_id=sid)
        assert exit_code == 0
        assert "6/10" in stderr
        assert "Soft search cap reached" in stderr
        assert _read_counter(sid) == 6

    def test_search_8_mid_warning_zone(self):
        """Search 8 (mid-warning zone): allowed with soft cap warning showing 8/10."""
        sid = "test-threshold-8"
        _seed_counter(sid, 7)
        exit_code, stdout, stderr = run_hook(_make_search_input(), session_id=sid)
        assert exit_code == 0
        assert "8/10" in stderr
        assert "Soft search cap reached" in stderr
        assert _read_counter(sid) == 8

    def test_search_10_last_allowed(self):
        """Search 10 (last allowed): allowed with soft cap warning showing 10/10."""
        sid = "test-threshold-10"
        _seed_counter(sid, 9)
        exit_code, stdout, stderr = run_hook(_make_search_input(), session_id=sid)
        assert exit_code == 0
        assert "10/10" in stderr
        assert "Soft search cap reached" in stderr
        assert _read_counter(sid) == 10

    def test_search_11_first_blocked(self):
        """Search 11 (first blocked): blocked with hard cap message."""
        sid = "test-threshold-11"
        _seed_counter(sid, 10)
        exit_code, stdout, stderr = run_hook(_make_search_input(), session_id=sid)
        assert exit_code == 2
        assert "Search cap exceeded" in stderr
        assert "10/10" in stderr
        # Counter should NOT be incremented on block
        assert _read_counter(sid) == 10

    def test_search_15_deep_block(self):
        """Search 15 (deep block): blocked with hard cap message."""
        sid = "test-threshold-15"
        _seed_counter(sid, 14)
        exit_code, stdout, stderr = run_hook(_make_search_input(), session_id=sid)
        assert exit_code == 2
        assert "Search cap exceeded" in stderr
        assert "14/10" in stderr
        # Counter should NOT be incremented on block
        assert _read_counter(sid) == 14


# =============================================================================
# Bypass Path Tests
# =============================================================================

class TestBypassPaths:
    """Tests for conditions that should bypass the search cap entirely."""

    def test_wrong_agent_name(self):
        """Wrong agent name should bypass cap (exit 0, no counting)."""
        sid = "test-bypass-wrong-agent"
        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            env_vars={"CLAUDE_AGENT_NAME": "other-agent"},
            session_id=sid,
        )
        assert exit_code == 0
        assert _read_counter(sid) is None  # No counter file created

    def test_no_agent_name(self):
        """No agent name set should bypass cap (exit 0, no counting)."""
        sid = "test-bypass-no-agent"
        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            env_vars={"CLAUDE_AGENT_NAME": ""},
            session_id=sid,
        )
        assert exit_code == 0
        assert _read_counter(sid) is None

    def test_non_bash_tool(self):
        """Non-Bash tool should bypass cap (exit 0, no counting)."""
        sid = "test-bypass-non-bash"
        input_json = json.dumps({
            "tool_name": "Read",
            "tool_input": {"file": "/tmp/test"},
        })
        exit_code, stdout, stderr = run_hook(input_json, session_id=sid)
        assert exit_code == 0
        assert _read_counter(sid) is None

    def test_non_maproom_command(self):
        """Non-maproom Bash command should bypass cap (exit 0, no counting)."""
        sid = "test-bypass-non-maproom"
        input_json = json.dumps({
            "tool_name": "Bash",
            "tool_input": {"command": "ls -la"},
        })
        exit_code, stdout, stderr = run_hook(input_json, session_id=sid)
        assert exit_code == 0
        assert _read_counter(sid) is None

    def test_maproom_context_command(self):
        """Maproom context command (not search) should bypass cap."""
        sid = "test-bypass-maproom-context"
        input_json = json.dumps({
            "tool_name": "Bash",
            "tool_input": {"command": "maproom context /path/to/file"},
        })
        exit_code, stdout, stderr = run_hook(input_json, session_id=sid)
        assert exit_code == 0
        assert _read_counter(sid) is None


# =============================================================================
# Error Handling Tests
# =============================================================================

class TestErrorHandling:
    """Tests for error conditions that should fail-open (exit 0)."""

    def test_malformed_json(self):
        """Malformed JSON input should fail-open (exit 0)."""
        sid = "test-error-malformed"
        exit_code, stdout, stderr = run_hook("not valid json", session_id=sid)
        assert exit_code == 0

    def test_missing_tool_input(self):
        """Missing tool_input field should fail-open (exit 0)."""
        sid = "test-error-missing-fields"
        input_json = json.dumps({"tool_name": "Bash"})
        exit_code, stdout, stderr = run_hook(input_json, session_id=sid)
        assert exit_code == 0

    def test_empty_command(self):
        """Empty command string should bypass cap (exit 0, no counting)."""
        sid = "test-error-empty-cmd"
        input_json = json.dumps({
            "tool_name": "Bash",
            "tool_input": {"command": ""},
        })
        exit_code, stdout, stderr = run_hook(input_json, session_id=sid)
        assert exit_code == 0
        assert _read_counter(sid) is None


# =============================================================================
# Counter State Tests
# =============================================================================

class TestCounterState:
    """Tests for counter file creation, reading, and corruption handling."""

    def test_counter_absent_creates_file(self):
        """When counter file is absent, first search creates it with value 1."""
        sid = "test-counter-absent"
        # Ensure no counter file exists
        path = _counter_path(sid)
        if os.path.exists(path):
            os.remove(path)

        exit_code, stdout, stderr = run_hook(_make_search_input(), session_id=sid)
        assert exit_code == 0
        assert _read_counter(sid) == 1

    def test_counter_present_increments(self):
        """When counter file exists with value 4, search increments to 5."""
        sid = "test-counter-present"
        _seed_counter(sid, 4)
        exit_code, stdout, stderr = run_hook(_make_search_input(), session_id=sid)
        assert exit_code == 0
        assert _read_counter(sid) == 5
        # No warning at count 5 (at soft cap, not above)
        assert "cap" not in stderr.lower()

    def test_counter_corrupt_treated_as_zero(self):
        """Corrupt counter file (non-integer) should be treated as 0."""
        sid = "test-counter-corrupt"
        path = _counter_path(sid)
        with open(path, "w") as f:
            f.write("abc")

        exit_code, stdout, stderr = run_hook(_make_search_input(), session_id=sid)
        assert exit_code == 0
        # Corrupt file read as 0, incremented to 1 -- no warning
        assert _read_counter(sid) == 1
        assert "cap" not in stderr.lower()


# =============================================================================
# Filesystem Error Tests (Fail-Open Verification)
# =============================================================================

class TestFilesystemErrors(unittest.TestCase):
    """Tests for fail-open behavior under filesystem stress.

    The hook wraps all logic in a try/except that catches Exception and
    exits 0 (fail-open). These tests verify that this safety mechanism
    works under real filesystem pressure -- permission errors, missing
    directories, and unwritable paths.
    """

    def setUp(self):
        """Track temporary directories and files for cleanup."""
        self._temp_dirs = []
        self._restricted_files = []

    def tearDown(self):
        """Restore permissions and clean up all test artifacts."""
        # Restore file permissions before removal
        for fpath in self._restricted_files:
            try:
                os.chmod(fpath, stat.S_IRUSR | stat.S_IWUSR)
                os.remove(fpath)
            except OSError:
                pass

        # Restore directory permissions and remove temp dirs (reverse order)
        for dpath in reversed(self._temp_dirs):
            try:
                os.chmod(dpath, stat.S_IRWXU)
            except OSError:
                pass
            try:
                # Remove any files inside the directory
                for entry in os.listdir(dpath):
                    entry_path = os.path.join(dpath, entry)
                    try:
                        os.chmod(entry_path, stat.S_IRUSR | stat.S_IWUSR)
                        os.remove(entry_path)
                    except OSError:
                        pass
                os.rmdir(dpath)
            except OSError:
                pass

    def test_unwritable_counter_path(self):
        """When counter path is a directory (not a file), hook should fail-open (exit 0).

        Places a directory at the expected counter file path. When the hook
        attempts to open() this path for reading or writing, it raises
        IsADirectoryError (a subclass of OSError), which is caught by the
        top-level except block.
        """
        sid = "test-fs-unwritable-path"
        counter_path = _counter_path(sid)

        # Place a directory where the counter file should be
        if os.path.exists(counter_path):
            os.remove(counter_path)
        os.makedirs(counter_path, exist_ok=True)
        self._temp_dirs.append(counter_path)

        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            session_id=sid,
        )

        assert exit_code == 0, (
            f"Expected fail-open (exit 0) when counter path is a directory, "
            f"got exit {exit_code}. stderr: {stderr}"
        )
        assert "warning" in stderr.lower(), (
            f"Expected warning on stderr when counter path is a directory. "
            f"stderr: {stderr}"
        )

    def test_readonly_counter_file(self):
        """When counter file has no permissions, hook should fail-open (exit 0).

        Pre-creates a counter file with value 4, then removes all
        permissions (chmod 0o000). The hook cannot read or write the file,
        causing an exception caught by the fail-open handler.
        """
        sid = "test-fs-readonly-file"
        counter_path = _counter_path(sid)

        # Pre-create the counter file with a normal value
        _seed_counter(sid, 4)
        self._restricted_files.append(counter_path)

        # Remove all permissions from the counter file
        os.chmod(counter_path, 0o000)

        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            session_id=sid,
        )

        assert exit_code == 0, (
            f"Expected fail-open (exit 0) when counter file is unreadable, "
            f"got exit {exit_code}. stderr: {stderr}"
        )
        assert "warning" in stderr.lower(), (
            f"Expected warning on stderr when counter file is unreadable. "
            f"stderr: {stderr}"
        )

    def test_nonexistent_tmp_path(self):
        """When counter path is a broken symlink, hook should fail-open (exit 0).

        Creates a symlink at the counter file path that points to a file
        inside a nonexistent directory. The hook's read_count() catches
        FileNotFoundError, returning 0. But write_count() attempts to open
        the symlink target for writing, raising FileNotFoundError (because
        the target directory doesn't exist), which is caught by fail-open.
        """
        sid = "test-fs-nonexistent-tmp"
        counter_path = _counter_path(sid)

        # Remove any existing file at the counter path
        if os.path.exists(counter_path) or os.path.islink(counter_path):
            os.remove(counter_path)

        # Create a symlink pointing to a file in a nonexistent directory
        broken_target = "/tmp/test-fs-nonexistent-dir-" + str(os.getpid()) + "/counter"
        os.symlink(broken_target, counter_path)
        self._restricted_files.append(counter_path)

        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            session_id=sid,
        )

        assert exit_code == 0, (
            f"Expected fail-open (exit 0) when counter is a broken symlink, "
            f"got exit {exit_code}. stderr: {stderr}"
        )
        assert "warning" in stderr.lower(), (
            f"Expected warning on stderr when counter is a broken symlink. "
            f"stderr: {stderr}"
        )


# =============================================================================
# Metrics Emission Tests
# =============================================================================

class TestMetrics:
    """Tests for opt-in metrics emission via MAPROOM_METRICS_ENABLED."""

    def test_soft_cap_metrics_enabled(self):
        """Soft cap warning emits metric to stderr when MAPROOM_METRICS_ENABLED=1."""
        sid = "test-metrics-soft-enabled"
        _seed_counter(sid, 5)
        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            env_vars={"MAPROOM_METRICS_ENABLED": "1"},
            session_id=sid,
        )
        assert exit_code == 0
        assert "Soft search cap reached" in stderr
        assert "METRIC:maproom.search_cap.soft_warning:1" in stderr

    def test_hard_cap_metrics_enabled(self):
        """Hard cap block emits metric to stderr when MAPROOM_METRICS_ENABLED=1."""
        sid = "test-metrics-hard-enabled"
        _seed_counter(sid, 10)
        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            env_vars={"MAPROOM_METRICS_ENABLED": "1"},
            session_id=sid,
        )
        assert exit_code == 2
        assert "Search cap exceeded" in stderr
        assert "METRIC:maproom.search_cap.hard_block:1" in stderr

    def test_metrics_disabled_by_default(self):
        """No METRIC: lines emitted when MAPROOM_METRICS_ENABLED is not set."""
        sid = "test-metrics-disabled"
        _seed_counter(sid, 5)
        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            session_id=sid,
        )
        assert exit_code == 0
        assert "Soft search cap reached" in stderr
        assert "METRIC:" not in stderr

    def test_metrics_enabled_true_string(self):
        """Metrics emitted when MAPROOM_METRICS_ENABLED=true."""
        sid = "test-metrics-true-str"
        _seed_counter(sid, 5)
        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            env_vars={"MAPROOM_METRICS_ENABLED": "true"},
            session_id=sid,
        )
        assert exit_code == 0
        assert "METRIC:maproom.search_cap.soft_warning:1" in stderr

    def test_metrics_enabled_yes_string(self):
        """Metrics emitted when MAPROOM_METRICS_ENABLED=yes."""
        sid = "test-metrics-yes-str"
        _seed_counter(sid, 5)
        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            env_vars={"MAPROOM_METRICS_ENABLED": "yes"},
            session_id=sid,
        )
        assert exit_code == 0
        assert "METRIC:maproom.search_cap.soft_warning:1" in stderr

    def test_metrics_not_emitted_for_false(self):
        """No METRIC: lines when MAPROOM_METRICS_ENABLED=false."""
        sid = "test-metrics-false-str"
        _seed_counter(sid, 5)
        exit_code, stdout, stderr = run_hook(
            _make_search_input(),
            env_vars={"MAPROOM_METRICS_ENABLED": "false"},
            session_id=sid,
        )
        assert exit_code == 0
        assert "Soft search cap reached" in stderr
        assert "METRIC:" not in stderr


# =============================================================================
# SessionEnd Cleanup Hook Tests
# =============================================================================

CLEANUP_HOOK_PATH = os.path.join(os.path.dirname(__file__), "cleanup-search-counter.py")


class TestCleanupHook:
    """Tests for the SessionEnd cleanup hook."""

    def test_cleanup_removes_counter_file(self):
        """Cleanup hook removes existing counter file for the session."""
        sid = "test-cleanup-exists"
        counter_path = _counter_path(sid)
        _seed_counter(sid, 7)
        assert os.path.exists(counter_path)

        env = os.environ.copy()
        env["CLAUDE_SESSION_ID"] = sid
        result = subprocess.run(
            ["python3", CLEANUP_HOOK_PATH],
            capture_output=True,
            text=True,
            env=env,
        )
        assert result.returncode == 0
        assert not os.path.exists(counter_path)

    def test_cleanup_no_file_exits_cleanly(self):
        """Cleanup hook exits cleanly when no counter file exists."""
        sid = "test-cleanup-nofile"
        counter_path = _counter_path(sid)
        if os.path.exists(counter_path):
            os.remove(counter_path)

        env = os.environ.copy()
        env["CLAUDE_SESSION_ID"] = sid
        result = subprocess.run(
            ["python3", CLEANUP_HOOK_PATH],
            capture_output=True,
            text=True,
            env=env,
        )
        assert result.returncode == 0


if __name__ == "__main__":
    import pytest
    pytest.main([__file__, "-v"])
