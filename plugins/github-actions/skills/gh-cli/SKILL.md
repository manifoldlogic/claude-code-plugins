# gh-cli

Guide for using the GitHub CLI (gh) to manage GitHub Actions workflows in the crewchief repository.

## Authentication Check (CRITICAL)

**Before using any `gh` commands, you MUST verify authentication:**

```bash
gh auth status
```

**If not authenticated**, STOP and tell the user:

> GitHub CLI is not authenticated. Please run `gh auth login` to authenticate before proceeding.

Do NOT attempt any `gh` commands until authentication is confirmed.

## Common Workflow Commands

### List Workflows

```bash
# List all workflows
gh workflow list

# List workflows with status
gh workflow list --all
```

### View Workflow Runs

```bash
# List recent workflow runs
gh run list

# List runs for a specific workflow
gh run list --workflow=ci.yml

# List failed runs only
gh run list --status=failure

# List runs for a specific branch
gh run list --branch=main
```

### View Run Details

```bash
# View a specific run (by ID or URL)
gh run view <run-id>

# View with job details
gh run view <run-id> --verbose

# View failed jobs
gh run view <run-id> --log-failed
```

### Download Logs

```bash
# Download all logs for a run
gh run download <run-id>

# Download specific artifact
gh run download <run-id> --name=<artifact-name>
```

### Trigger Workflows

```bash
# Trigger a workflow_dispatch workflow
gh workflow run <workflow-name>

# Trigger with inputs
gh workflow run <workflow-name> --field=environment=staging
```

### Rerun Workflows

```bash
# Rerun a failed workflow
gh run rerun <run-id>

# Rerun only failed jobs
gh run rerun <run-id> --failed
```

### Cancel Workflows

```bash
# Cancel a running workflow
gh run cancel <run-id>
```

## Troubleshooting Failed Workflows

1. **Check authentication first:**
   ```bash
   gh auth status
   ```

2. **List recent failures:**
   ```bash
   gh run list --status=failure --limit=5
   ```

3. **View failed run logs:**
   ```bash
   gh run view <run-id> --log-failed
   ```

4. **Download full logs for analysis:**
   ```bash
   gh run download <run-id> --dir=/tmp/workflow-logs
   ```

## Secrets and Variables

```bash
# List secrets (names only, not values)
gh secret list

# Set a secret
gh secret set SECRET_NAME

# List environment variables
gh variable list
```

## Best Practices

1. **Always check auth status** before running any commands
2. **Use `--json` flag** for parsing output programmatically
3. **Specify workflow by filename** (e.g., `ci.yml`) not display name
4. **Use `--limit`** to reduce output when listing many items
5. **Check PR status** before and after pushing changes

## Error Handling

Common errors and solutions:

| Error | Solution |
|-------|----------|
| `gh: command not found` | Install GitHub CLI: `brew install gh` or see https://cli.github.com/ |
| `not logged in` | Run `gh auth login` |
| `HTTP 401` | Re-authenticate: `gh auth login` |
| `HTTP 403` | Check repository permissions |
| `HTTP 404` | Verify workflow/run exists, check repository name |

## JSON Output

For programmatic use, add `--json` flag:

```bash
# List runs as JSON
gh run list --json status,conclusion,databaseId,workflowName

# View run as JSON
gh run view <run-id> --json jobs,status,conclusion
```
