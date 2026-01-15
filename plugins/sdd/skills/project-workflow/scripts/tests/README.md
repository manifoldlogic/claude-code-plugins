# SDD Loop Controller Tests

This directory contains tests for the SDD Loop Controller (`sdd-loop.sh`).

## Test Types

### Unit Tests (`test-sdd-loop.sh`)

Located in the parent `scripts/` directory. Unit tests use mocked dependencies to test:
- Command-line argument parsing
- Configuration hierarchy
- Safety limits (max iterations, max errors, timeout)
- Phase boundary detection
- Signal handling setup
- Error handling and recovery

**Run unit tests:**
```bash
cd /path/to/project-workflow/scripts
./test-sdd-loop.sh
```

### Integration Tests (`integration-test-sdd-loop.sh`)

Located in this `tests/` directory. Integration tests use **real Claude Code** to validate end-to-end workflow:
- Real Claude Code CLI execution
- Actual task completion
- Status checkbox updates
- Full sdd-loop.sh workflow

**Run integration tests:**
```bash
cd /path/to/project-workflow/scripts/tests
./integration-test-sdd-loop.sh
```

## Integration Test Requirements

### Prerequisites

1. **Claude Code CLI** - Must be installed and accessible in PATH
   ```bash
   # Verify installation
   claude --version
   ```

2. **Claude API Access** - One of:
   - `ANTHROPIC_API_KEY` environment variable set
   - `CLAUDE_API_KEY` environment variable set
   - Valid credentials in `~/.anthropic/credentials`

3. **jq** - Required for JSON parsing
   ```bash
   # Install on Debian/Ubuntu
   apt-get install jq

   # Install on macOS
   brew install jq
   ```

### API Usage Notes

- Integration tests consume Claude API credits
- Each test run executes 1 task (approximately 1 API call)
- Estimated cost per run: Minimal (simple task)
- Typical execution time: 30-90 seconds

## Running Tests

### Quick Start

```bash
# Run unit tests (no API key required)
../test-sdd-loop.sh

# Run integration tests (requires API key)
./integration-test-sdd-loop.sh
```

### Integration Test Options

```bash
# Show help
./integration-test-sdd-loop.sh --help

# Verbose output (useful for debugging)
./integration-test-sdd-loop.sh --verbose

# Keep test directory after completion (for debugging failures)
./integration-test-sdd-loop.sh --skip-cleanup

# Combined options
./integration-test-sdd-loop.sh --verbose --skip-cleanup
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 1 | Test failed |
| 2 | Prerequisites not met |

## CI/CD Integration

### GitHub Actions Example

```yaml
integration-tests:
  runs-on: ubuntu-latest
  # Only run on main branch or with explicit trigger
  if: github.ref == 'refs/heads/main' || github.event_name == 'workflow_dispatch'
  steps:
    - uses: actions/checkout@v4

    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y jq

    - name: Install Claude Code CLI
      run: |
        # Claude Code installation steps
        npm install -g @anthropic/claude-code

    - name: Run integration tests
      env:
        ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      run: |
        cd plugins/sdd/skills/project-workflow/scripts/tests
        ./integration-test-sdd-loop.sh --verbose
```

### Skipping Integration Tests

For CI/CD environments without API access, you can skip integration tests:

```yaml
- name: Run integration tests
  if: env.ANTHROPIC_API_KEY != ''
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  run: ./integration-test-sdd-loop.sh
```

## Test Fixtures

### Directory Structure

```
tests/
├── integration-test-sdd-loop.sh   # Main integration test script
├── README.md                       # This file
└── test-fixtures/
    └── TEST_integration/
        └── tasks/
            └── TEST.1001_simple-test.md  # Sample test task template
```

### Test Fixture: TEST.1001

A minimal, deterministic task that:
1. Creates a file at a predictable location
2. Writes specific content ("Integration test success")
3. Is easy to validate programmatically

The integration test script creates a fresh copy of this task structure in `/tmp/` for each run.

## Troubleshooting

### Test Fails: "Claude Code CLI not found"

Install Claude Code:
```bash
npm install -g @anthropic/claude-code
```

Or verify it's in your PATH:
```bash
which claude
```

### Test Fails: "Task validation failed"

1. Run with `--verbose --skip-cleanup` to see details:
   ```bash
   ./integration-test-sdd-loop.sh --verbose --skip-cleanup
   ```

2. Check the test directory printed at the end:
   ```bash
   cat /tmp/sdd-integration-test-YYYYMMDD-HHMMSS-PID/sdd-loop-output.log
   ```

3. Verify the task file status:
   ```bash
   cat /tmp/sdd-integration-test-*/\_SDD/tickets/TEST_integration-test/tasks/TEST.1001_simple-integration-test.md
   ```

### Test Fails: API Authentication

1. Verify your API key:
   ```bash
   echo $ANTHROPIC_API_KEY
   ```

2. Or check Claude's credentials:
   ```bash
   cat ~/.anthropic/credentials
   ```

3. Test Claude directly:
   ```bash
   claude -p "echo 'test'"
   ```

### Test Times Out

- Default timeout is 120 seconds
- If Claude is slow, check network connectivity
- Increase timeout by editing `TEST_TIMEOUT` in the script

## Development

### Adding New Integration Tests

1. Create a new test task in `test-fixtures/`
2. Add validation logic to `integration-test-sdd-loop.sh`
3. Document the new test in this README

### Test Design Principles

1. **Deterministic**: Tasks should produce predictable, verifiable results
2. **Fast**: Use simple tasks to minimize execution time
3. **Isolated**: Each test run creates fresh temporary directories
4. **Cleanup**: Always clean up test artifacts (unless debugging)
5. **Graceful Skip**: Tests should skip gracefully when prerequisites are missing
