#!/usr/bin/env python3
"""
Unit tests for block-catastrophic-commands.py hook.

Tests verify that catastrophic commands are blocked while safe commands
are allowed. Covers all 3 pattern categories: root deletion, root permission
compromise, and disk wiping.
"""
import subprocess
import json
import os

# Path to the hook script
HOOK_PATH = os.path.join(os.path.dirname(__file__), "block-catastrophic-commands.py")


def run_hook(command: str) -> subprocess.CompletedProcess:
    """Run the hook with the given command and return the result."""
    input_json = json.dumps({"tool_input": {"command": command}})
    return subprocess.run(
        ["python3", HOOK_PATH],
        input=input_json,
        capture_output=True,
        text=True
    )


# =============================================================================
# Catastrophic Pattern Tests (should block - exit code 2)
# =============================================================================

class TestRootDeletionBlocking:
    """Tests for root filesystem deletion patterns."""

    def test_blocks_rm_rf_root(self):
        """rm -rf / should be blocked."""
        result = run_hook("rm -rf /")
        assert result.returncode == 2
        assert "root filesystem deletion" in result.stderr

    def test_blocks_rm_rf_root_glob(self):
        """rm -rf /* should be blocked."""
        result = run_hook("rm -rf /*")
        assert result.returncode == 2
        assert "root filesystem deletion" in result.stderr


class TestRootPermissionBlocking:
    """Tests for root permission compromise patterns."""

    def test_blocks_chmod_777_root(self):
        """chmod -R 777 / should be blocked."""
        result = run_hook("chmod -R 777 /")
        assert result.returncode == 2
        assert "root permission compromise" in result.stderr

    def test_blocks_chmod_777_root_glob(self):
        """chmod -R 777 /* should be blocked."""
        result = run_hook("chmod -R 777 /*")
        assert result.returncode == 2
        assert "root permission compromise" in result.stderr


class TestDiskWipeBlocking:
    """Tests for disk wiping patterns."""

    def test_blocks_dd_to_sda(self):
        """dd to /dev/sda should be blocked."""
        result = run_hook("dd if=/dev/zero of=/dev/sda")
        assert result.returncode == 2
        assert "disk wipe" in result.stderr

    def test_blocks_dd_to_sdb1(self):
        """dd to /dev/sdb1 should be blocked (partition)."""
        result = run_hook("dd if=/dev/zero of=/dev/sdb1")
        assert result.returncode == 2
        assert "disk wipe" in result.stderr


# =============================================================================
# Safe Command Tests (should allow - exit code 0)
# =============================================================================

class TestSafeCommandsAllowed:
    """Tests for safe commands that should be allowed."""

    def test_allows_tmp_deletion(self):
        """rm -rf /tmp/test should be allowed."""
        result = run_hook("rm -rf /tmp/test")
        assert result.returncode == 0

    def test_allows_chmod_755(self):
        """chmod 755 /usr/bin/script should be allowed."""
        result = run_hook("chmod 755 /usr/bin/script")
        assert result.returncode == 0

    def test_allows_dd_to_file(self):
        """dd to regular file should be allowed."""
        result = run_hook("dd if=/dev/zero of=/tmp/test")
        assert result.returncode == 0

    def test_allows_regular_rm(self):
        """Regular rm without -rf should be allowed."""
        result = run_hook("rm /tmp/file.txt")
        assert result.returncode == 0

    def test_allows_ls_command(self):
        """ls command should be allowed."""
        result = run_hook("ls -la /")
        assert result.returncode == 0


# =============================================================================
# Edge Case Tests
# =============================================================================

class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    def test_blocks_rm_rf_root_trailing_space(self):
        """rm -rf / with trailing space should be blocked."""
        result = run_hook("rm -rf / ")
        assert result.returncode == 2

    def test_allows_rm_rf_tmp_subdir(self):
        """rm -rf /tmp/subdir should be allowed."""
        result = run_hook("rm -rf /tmp/subdir/")
        assert result.returncode == 0

    def test_allows_chmod_recursive_non_777(self):
        """chmod -R with non-777 permissions should be allowed."""
        result = run_hook("chmod -R 755 /var/www")
        assert result.returncode == 0

    def test_blocks_multiple_slashes(self):
        """rm -rf // (multiple slashes) should be blocked."""
        result = run_hook("rm -rf //")
        assert result.returncode == 2

    def test_allows_dd_to_loop_device(self):
        """dd to /dev/loop0 should be allowed (not sd*)."""
        result = run_hook("dd if=/dev/zero of=/dev/loop0")
        assert result.returncode == 0

    def test_error_handling_malformed_json(self):
        """Malformed JSON should allow command (fail-safe)."""
        result = subprocess.run(
            ["python3", HOOK_PATH],
            input="not valid json",
            capture_output=True,
            text=True
        )
        # Should exit 0 (allow) on error as fail-safe
        assert result.returncode == 0


if __name__ == "__main__":
    import pytest
    pytest.main([__file__, "-v"])
