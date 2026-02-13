# Master Status Board Examples

Multi-repository SDD status aggregator with recommended actions for autonomous workflows.

## Basic Usage

### Scan Default Workspace

```bash
# Uses defaults: --specs-root /workspace/_SPECS/ --repos-root /workspace/repos/
./master-status-board.sh

# Or specify roots explicitly
./master-status-board.sh --specs-root /workspace/_SPECS/ --repos-root /workspace/repos/
```

### Output Fields

The script outputs JSON with these top-level fields:
- `timestamp` - ISO 8601 timestamp of scan
- `specs_root` - Absolute path to specs root (SDD data)
- `repos_root` - Absolute path to repos root (code repositories)
- `repos` - Array of repository objects with SDD directories
- `summary` - Aggregated counts across all repos
- `recommended_action` - Next action for autonomous workflow

## Summary-Only Mode

Use `--summary-only` or `-s` for just the summary without per-repo details:

```bash
./master-status-board.sh --summary-only
```

Output:
```json
{
  "timestamp": "2026-01-15T10:30:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "summary": {
    "total_repos": 3,
    "total_tickets": 12,
    "total_tasks": 45,
    "pending": 5,
    "completed": 10,
    "tested": 8,
    "verified": 22
  },
  "recommended_action": {
    "action": "none",
    "reason": "Summary-only mode - full scan required for recommendation"
  }
}
```

Note: In summary-only mode, `recommended_action` cannot compute a specific task because repo details are not available.

## Verbose Mode

Use `--verbose` or `-v` to see timing information on stderr:

```bash
./master-status-board.sh --verbose
```

Stderr output:
```
[0.12s] Scanned repo-a (3 tickets, 15 tasks)
[0.25s] Scanned repo-b (2 tickets, 8 tasks)
[0.38s] Total: 5 tickets, 23 tasks in 0.38s
```

Combined with jq for clean stdout:
```bash
./master-status-board.sh --verbose 2>&1 | tee /dev/stderr | head -1 | jq .summary
```

## Debug Mode

Use `--debug` or set `DEBUG=true` for detailed internal logging:

```bash
./master-status-board.sh --debug 2>&1 | grep '\[DEBUG\]'

# Or via environment variable
DEBUG=true ./master-status-board.sh
```

## Custom Root Directories

### Named Options

```bash
# Custom specs and repos locations
./master-status-board.sh --specs-root /custom/_SPECS/ --repos-root /custom/repos/
```

### Environment Variables

```bash
# New env vars
SPECS_ROOT=/custom/_SPECS REPOS_ROOT=/custom/repos bash master-status-board.sh

# Deprecated env var (still works but logs warning)
WORKSPACE_ROOT=/custom/repos bash master-status-board.sh
```

When using the deprecated `WORKSPACE_ROOT` variable, a warning is logged to stderr:
```
[WARN] WORKSPACE_ROOT is deprecated. Use SPECS_ROOT and REPOS_ROOT instead.
```

## Extracting Specific Data

### Get Summary Only

```bash
./master-status-board.sh | jq '.summary'
```

### Get Recommended Action

```bash
./master-status-board.sh | jq '.recommended_action'
```

Example output:
```json
{
  "action": "do-task",
  "repo": "my-project",
  "ticket": "AUTH-123",
  "task": "AUTH-123.1002",
  "task_file": "/workspace/_SPECS/my-project/tickets/AUTH-123/tasks/AUTH-123.1002_implement-oauth.md",
  "sdd_root": "/workspace/_SPECS/my-project",
  "reason": "Next pending task in highest priority ticket"
}
```

### List All Repos with SDD

```bash
./master-status-board.sh | jq '.repos[].name'
```

### Find Repos with Pending Work

```bash
./master-status-board.sh | jq '.repos[] | select(.summary.pending > 0) | {name, pending: .summary.pending}'
```

### Get Agent-Ready Tickets

```bash
./master-status-board.sh | jq '[.repos[].tickets[] | select(.autogate.agent_ready == true)] | .[].ticket_id'
```

## SDDLOOP-3 Integration (Ralph Loop Controller)

The `recommended_action` field is designed for integration with autonomous loop controllers like SDDLOOP-3 (Ralph).

### Parsing Recommended Action

```bash
#!/bin/bash
# Example: ralph-loop-controller.sh

# Get the full status
status=$(./master-status-board.sh)

# Extract action type
action=$(echo "$status" | jq -r '.recommended_action.action')

case "$action" in
    "do-task")
        # Extract task details
        task_id=$(echo "$status" | jq -r '.recommended_action.task')
        sdd_root=$(echo "$status" | jq -r '.recommended_action.sdd_root')
        task_file=$(echo "$status" | jq -r '.recommended_action.task_file')
        reason=$(echo "$status" | jq -r '.recommended_action.reason')

        echo "Next task: $task_id"
        echo "Reason: $reason"
        echo "SDD Root: $sdd_root"

        # Set environment variable for SDD commands
        export SDD_ROOT_DIR="$sdd_root"

        # Execute the task (example)
        # /sdd:do-task "$task_id"
        ;;
    "none")
        reason=$(echo "$status" | jq -r '.recommended_action.reason')
        echo "No work available: $reason"
        # Loop should pause or wait for new work
        ;;
esac
```

### Setting SDD_ROOT_DIR for Cross-Repo Work

When working across multiple repositories, extract `sdd_root` from the recommended action:

```bash
# Get recommended action with sdd_root
recommended=$(./master-status-board.sh | jq '.recommended_action')

# Extract and export SDD_ROOT_DIR
export SDD_ROOT_DIR=$(echo "$recommended" | jq -r '.sdd_root')

# Now SDD commands will use the correct repo's SDD directory
echo "Working in: $SDD_ROOT_DIR"
# Example output: Working in: /workspace/_SPECS/claude-code-plugins
```

### Handling "none" Action

When `action` is "none", the loop controller should:

1. **Check the reason** - Understand why no work is available
2. **Wait or poll** - Sleep and retry after interval
3. **Log state** - Record for observability

Possible reasons for "none":
- "No agent-ready work remaining" - All tickets are gated or complete
- "All agent-ready work completed" - Tickets exist but all tasks are verified
- "No scan data provided" - Error case, should not normally occur
- "Summary-only mode - full scan required for recommendation" - Used --summary-only flag

Example handling:
```bash
action=$(./master-status-board.sh | jq -r '.recommended_action.action')
reason=$(./master-status-board.sh | jq -r '.recommended_action.reason')

if [ "$action" = "none" ]; then
    echo "Loop pausing: $reason"

    case "$reason" in
        "No agent-ready work remaining")
            # Check if any tickets need manual gate updates
            echo "Consider reviewing .autogate.json files for blocked tickets"
            ;;
        "All agent-ready work completed")
            # All done! Consider creating new tickets or archiving
            echo "All agent-ready work complete. Consider running /sdd:archive"
            ;;
    esac

    # Wait before next poll
    sleep 60
fi
```

### Complete Loop Example

```bash
#!/bin/bash
# ralph-loop.sh - Simple autonomous loop controller

POLL_INTERVAL=30

while true; do
    echo "Polling for work at $(date -Iseconds)..."

    # Get status (uses default --specs-root and --repos-root)
    status=$(./master-status-board.sh)
    action=$(echo "$status" | jq -r '.recommended_action.action')

    if [ "$action" = "do-task" ]; then
        task=$(echo "$status" | jq -r '.recommended_action.task')
        sdd_root=$(echo "$status" | jq -r '.recommended_action.sdd_root')

        echo "Executing task: $task"
        export SDD_ROOT_DIR="$sdd_root"

        # Execute task (integration with Claude Code)
        # claude --sdd:do-task "$task"

    else
        reason=$(echo "$status" | jq -r '.recommended_action.reason')
        echo "No work: $reason"
        echo "Sleeping for ${POLL_INTERVAL}s..."
        sleep $POLL_INTERVAL
    fi
done
```

## Handling Missing Repos

In the two-root model, a specs directory may exist without a matching code repository. The status board handles this gracefully:

```json
{
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "claude-code-plugins",
      "sdd_path": "/workspace/_SPECS/claude-code-plugins",
      "repo_path": "/workspace/repos/claude-code-plugins/",
      "tickets": ["..."],
      "summary": {"total_tickets": 3, "total_tasks": 12, "...": "..."}
    },
    {
      "name": "dev-container",
      "sdd_path": "/workspace/_SPECS/dev-container",
      "repo_path": null,
      "repo_status": "repo_not_found",
      "tickets": [],
      "tasks": []
    }
  ]
}
```

When `repo_path` is `null` and `repo_status` is `"repo_not_found"`:
- The specs directory exists but no matching code repository was found under `repos_root`
- Tickets and tasks are still listed (they exist in the specs directory)
- The repo will not be recommended for task execution since there is no working directory

## JSON Output Schema

### Top-Level Schema

```json
{
  "timestamp": "string (ISO 8601)",
  "specs_root": "string (absolute path to specs root)",
  "repos_root": "string (absolute path to repos root)",
  "repos": ["array of repo objects"],
  "summary": {"object with aggregated counts"},
  "recommended_action": {"object with next action"}
}
```

### Repo Object Schema

```json
{
  "name": "string (specs directory name)",
  "sdd_path": "string (path to specs directory, e.g. /workspace/_SPECS/my-project)",
  "repo_path": "string or null (path to code repo, null if not found)",
  "repo_status": "string (present only when repo_path is null: 'repo_not_found')",
  "tickets": ["array of ticket objects"],
  "summary": {
    "total_tickets": "integer",
    "total_tasks": "integer",
    "pending": "integer",
    "completed": "integer",
    "tested": "integer",
    "verified": "integer"
  }
}
```

### Ticket Object Schema

```json
{
  "ticket_id": "string",
  "name": "string (from README.md title)",
  "path": "string (absolute path)",
  "autogate": {
    "ready": "boolean (default: true)",
    "agent_ready": "boolean (default: false)",
    "priority": "integer or null",
    "stop_at_phase": "integer or null"
  },
  "tasks": ["array of task objects"],
  "summary": {
    "total_tasks": "integer",
    "pending": "integer",
    "completed": "integer",
    "tested": "integer",
    "verified": "integer"
  }
}
```

### Task Object Schema

```json
{
  "file": "string (absolute path)",
  "task_id": "string (e.g., TICKET.1001)",
  "task_completed": "boolean",
  "tests_pass": "boolean",
  "verified": "boolean"
}
```

### Recommended Action Schema

When work is available (`action: "do-task"`):
```json
{
  "action": "do-task",
  "repo": "string (repo name)",
  "ticket": "string (ticket ID)",
  "task": "string (task ID)",
  "task_file": "string (absolute path to task file)",
  "sdd_root": "string (absolute path to specs directory)",
  "reason": "string (human-readable explanation)"
}
```

When no work is available (`action: "none"`):
```json
{
  "action": "none",
  "reason": "string (explanation)"
}
```

## Performance Characteristics

- **Typical scan time**: < 2 seconds for workspace with 5-10 repos
- **Scaling**: Linear with number of repos, tickets, and tasks
- **Memory**: Minimal - streams data, no large data structures
- **Dependencies**: Requires `jq` for recommended_action computation

### Performance Tips

1. Use `--summary-only` when you don't need per-repo details
2. For very large workspaces, consider scanning subsets
3. Cache results if polling frequently (results valid for ~30s typically)

## Troubleshooting

### Invalid JSON Output

```bash
# Validate JSON
./master-status-board.sh | jq . > /dev/null
echo $?  # Should be 0
```

### Missing recommended_action

If `recommended_action` is null:
1. Check if `jq` is installed: `command -v jq`
2. Run with `--debug` to see internal processing
3. Verify repos have valid ticket structures

### Permission Errors

```bash
# Check for permission issues
./master-status-board.sh 2>&1 | grep -i permission
```

### No Repos Found

```bash
# Verify specs directories exist under _SPECS root
ls /workspace/_SPECS/

# Check that matching repos exist under repos root
ls /workspace/repos/

# Run with debug mode to trace discovery
./master-status-board.sh --debug 2>&1 | grep "Found"
```

### Missing Repo for Specs Directory

If a specs directory exists but the matching repo is not found:

```bash
# Check the JSON output for repo_not_found entries
./master-status-board.sh | jq '.repos[] | select(.repo_status == "repo_not_found")'
```

Possible causes:
1. **Repo not cloned** - Clone the repository into `/workspace/repos/`
2. **Name mismatch** - The specs directory name must match the repo directory name
3. **Repo path incorrect** - Verify `--repos-root` points to the correct directory

### Git Root Discovery Issues

If the working directory is incorrect for task execution:

```bash
# Check what git root was discovered for a repo
./master-status-board.sh --debug 2>&1 | grep "git root"
```

In the two-root model, the script discovers the git root within the repo directory. For repos where the git root differs from the parent directory name (e.g., a monorepo), the working directory is set to the git root path rather than the parent.

### Path Bounds Validation Errors

If you see path bounds validation errors:

```bash
# Verify both roots are absolute paths
./master-status-board.sh --specs-root /workspace/_SPECS/ --repos-root /workspace/repos/

# Check that paths exist
ls -d /workspace/_SPECS/ /workspace/repos/
```

Both `--specs-root` and `--repos-root` must be absolute paths to existing directories.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (including empty workspace) |
| 1 | Specs root or repos root directory does not exist |
| 2 | Invalid arguments |

## Related Documentation

- [SDD Plugin README](/plugins/sdd/README.md) - Full plugin documentation
- [Workflow Overview](/plugins/sdd/skills/project-workflow/references/workflow-overview.md)
- [Autogate Configuration](/plugins/sdd/README.md#work-gates) - `.autogate.json` schema
