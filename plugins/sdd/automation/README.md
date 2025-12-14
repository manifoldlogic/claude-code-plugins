# SDD Automation Framework

This directory contains the automated workflow orchestrator for Spec-Driven Development (SDD). The framework manages the end-to-end workflow of fetching tickets, making decisions, and executing tasks through Claude agents.

## Architecture

The framework follows a modular architecture with clear separation of concerns:

```
automation/
├── orchestrator.sh          # Main entry point and workflow coordinator
├── config/                  # Configuration files
│   └── default.json         # Default configuration
├── lib/                     # Shared libraries
│   └── common.sh            # Logging, JSON helpers, validation
├── modules/                 # Pluggable workflow modules
│   ├── state-manager.sh     # State persistence
│   ├── recovery-handler.sh  # Error recovery and retry logic
│   ├── jira-adapter.sh      # JIRA API integration
│   ├── decision-engine.sh   # Claude-based decision making
│   └── sdd-executor.sh      # SDD command execution
└── tests/                   # Comprehensive test suite
    ├── test-harness.sh      # Test framework
    ├── test_*.sh            # Test suites
    └── fixtures/            # Test data
```

## Core Components

### Orchestrator (`orchestrator.sh`)

The main entry point that coordinates the entire workflow:

- **Argument Parsing**: Handles command-line arguments and input modes
- **Configuration Loading**: Loads and validates configuration
- **Module Loading**: Dynamically loads workflow modules
- **Run Initialization**: Creates run directories and state files
- **Workflow Execution**: Coordinates module execution
- **Error Handling**: Manages errors and recovery

### Common Library (`lib/common.sh`)

Shared utilities used throughout the framework:

- **Logging**: Structured logging with sanitization (redacts tokens/passwords)
- **JSON Helpers**: Parse, validate, and extract JSON data
- **Atomic Write**: Safe file writing with proper permissions
- **Path Validation**: Security checks for path traversal

### Modules

Each module provides a specific capability and returns JSON responses:

- **state-manager.sh**: Persist and load workflow state
- **recovery-handler.sh**: Retry failed operations, create checkpoints
- **jira-adapter.sh**: Fetch tickets and details from JIRA
- **decision-engine.sh**: Use Claude to make workflow decisions
- **sdd-executor.sh**: Execute SDD commands for ticket processing

## Configuration

Configuration is loaded from `config/default.json` and can be overridden via:

1. Custom config file: `--config /path/to/config.json`
2. Environment variables: `SDD_LOG_LEVEL=debug`, `SDD_ROOT_DIR=/custom/path`

Configuration sections:

- **sdd_root**: Base directory for SDD data
- **retry**: Retry attempts, delays, backoff multiplier
- **checkpoint**: Checkpoint frequency and limits
- **decision**: Risk tolerance, timeout settings
- **logging**: Log level and format
- **tools**: Paths to external tools (claude, acli, gh)

## Usage

### Basic Usage

```bash
# Process tickets from JQL query
./orchestrator.sh --jql "project = ASDW AND status = 'In Progress'"

# Process specific tickets
./orchestrator.sh --tickets ASDW-1,ASDW-2,ASDW-3

# Process from epic
./orchestrator.sh --epic EPIC-123

# Resume a previous run
./orchestrator.sh --resume 20231214-120000-abc12345

# Dry run (no actual execution)
./orchestrator.sh --jql "project = ASDW" --dry-run
```

### Options

- `--jql QUERY`: Fetch tickets using JQL query
- `--epic ID`: Process all tickets in an epic
- `--team NAME`: Process tickets for a team
- `--tickets IDS`: Process specific tickets (comma-separated)
- `--resume RUN_ID`: Resume a previous run
- `--dry-run`: Preview without executing
- `--verbose`: Enable verbose output
- `--config FILE`: Use custom configuration
- `--help`: Show usage information
- `--version`: Show version

## State Management

Each run creates a unique directory under `$SDD_ROOT/automation/runs/`:

```
runs/20231214-120000-abc12345/
├── state.json           # Current workflow state
├── checkpoints/         # Recovery checkpoints
├── decisions/           # Decision logs
└── logs/                # Execution logs
    └── run.log
```

### State File Format

```json
{
  "run_id": "20231214-120000-abc12345",
  "status": "running",
  "input_type": "jql",
  "input_value": "project = ASDW",
  "started_at": "2023-12-14T12:00:00Z",
  "tickets": ["ASDW-1", "ASDW-2"],
  "current_ticket": "ASDW-1",
  "completed_tickets": []
}
```

## Testing

Comprehensive test suite with 80+ tests covering:

- Configuration loading and validation
- Common utilities (logging, JSON, paths)
- Module loading and interface validation
- Run initialization
- Security (path traversal, injection, sanitization)
- Integration (end-to-end workflows)

### Running Tests

```bash
# Run all tests
cd tests
./run_all_tests.sh

# Run specific test suite
./test_configuration.sh
./test_common_utilities.sh
./test_module_loading.sh
./test_run_initializer.sh
./test_security.sh
./test_integration.sh

# Generate coverage report
./generate_coverage.sh
```

### Test Fixtures

Test fixtures are located in `tests/fixtures/`:

- **configs/**: Valid and invalid configuration files
- **modules/**: Test modules (valid, missing functions, syntax errors)
- **states/**: Sample state files (initial, in-progress, corrupted)

## Security

The framework implements multiple security measures:

1. **Path Traversal Prevention**: All paths validated against traversal attempts
2. **Path Scope Validation**: Paths must be within SDD_ROOT
3. **Log Sanitization**: Automatic redaction of tokens, passwords, auth headers
4. **File Permissions**: Run directories (700), state files (600)
5. **JSON Validation**: All JSON inputs validated before processing
6. **Input Sanitization**: Special characters handled safely

## Error Handling

The framework uses structured error handling with specific exit codes:

- `0`: Success
- `1`: Invalid arguments or usage error
- `2`: Configuration error (missing file, invalid JSON, validation failure)
- `3`: Module loading error (missing module, invalid interface)
- `4`: Initialization error (directory creation, permission issues)
- `5`: Workflow execution error
- `6`: State management error
- `8`: Permission error

### Recovery Features

- **Automatic Retry**: Failed operations retried with exponential backoff
- **Checkpoints**: Workflow progress saved at configurable intervals
- **Resume**: Resume interrupted runs from last checkpoint
- **Error Logs**: Detailed error information in run logs

## Development

### Adding a New Module

1. Create module file in `modules/` directory
2. Implement required functions (depends on module type)
3. Return JSON: `{"success": true/false, "data": {...}, "error": "..."}`
4. Add tests in `tests/fixtures/modules/`
5. Update `load_modules()` in `orchestrator.sh`

### Module Interface

All modules should:

- Return valid JSON
- Use `{"success": true}` for successful operations
- Use `{"success": false, "error": "..."}` for failures
- Log using functions from `lib/common.sh`
- Handle errors gracefully without crashing

### Code Style

- Use `set -euo pipefail` in all scripts
- Document functions with comments
- Use descriptive variable names
- Follow existing patterns for consistency
- Add tests for new functionality

## Logging

Logs are written to:

- **Console**: INFO and above (unless quiet mode)
- **File**: All levels to `${RUN_DIR}/logs/run.log`

Log format:

```
2023-12-14T12:00:00Z|INFO|component|Message here
```

Log levels:

- **DEBUG**: Detailed diagnostic information
- **INFO**: General informational messages
- **WARN**: Warning messages (non-critical issues)
- **ERROR**: Error messages (critical failures)

## Monitoring

Monitor workflow execution through:

1. **State File**: Check `state.json` for current status
2. **Log Files**: Review `run.log` for detailed execution
3. **Exit Code**: Check script exit code for success/failure
4. **Decision Logs**: Review `decisions/` for AI decision records

## Troubleshooting

### Common Issues

**Issue**: Configuration validation fails
**Solution**: Check config file syntax with `jq . config.json`

**Issue**: Module loading fails
**Solution**: Verify all modules exist and have required functions

**Issue**: Permission denied errors
**Solution**: Ensure write access to `$SDD_ROOT` directory

**Issue**: Run initialization fails
**Solution**: Check disk space and directory permissions

### Debug Mode

Enable debug logging:

```bash
export SDD_LOG_LEVEL=debug
./orchestrator.sh --jql "..." --verbose
```

## Performance

The framework is optimized for:

- **Fast startup**: Lazy loading of modules
- **Efficient state**: JSON state files with atomic writes
- **Smart retry**: Exponential backoff prevents resource exhaustion
- **Checkpointing**: Resume from last checkpoint, not start

## License

This framework is part of the SDD plugin for Claude Code.

## Support

For issues or questions:

1. Check test suite for examples: `tests/`
2. Review logs: `${RUN_DIR}/logs/run.log`
3. Enable debug mode for detailed output
4. Consult architecture documentation in ticket planning docs
