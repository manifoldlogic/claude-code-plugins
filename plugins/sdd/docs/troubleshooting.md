# Troubleshooting Guide

Common issues and solutions for the SDD plugin.

**Version**: 1.0.0
**Last Updated**: 2025-12-11

---

## How to Use This Guide

1. Find your issue by error message or symptom
2. Follow the resolution steps
3. If issue persists, see [Getting Help](#getting-help)

**Quick Links**:
- [Planning Issues](#planning-phase-issues)
- [Review/Decompose Issues](#reviewdecompose-issues)
- [Execution Issues](#execution-issues)
- [Verification Issues](#verification-issues)
- [Archive Issues](#archive-issues)
- [General Issues](#general-issues)
- [Recovery Procedures](#recovery-procedures)
- [Loop Controller Issues](#loop-controller-issues)

---

## Planning Phase Issues

### "Ticket directory already exists"

**Error**:
```
ERROR: Ticket directory already exists: DEMO_example-ticket
```

**Cause**: Attempting to initialize a ticket with an ID that already exists.

**Solution**:
1. Check existing tickets: `/sdd:tasks-status`
2. If ticket exists and is active, proceed with planning instead
3. If old/abandoned, use a different TICKET_ID
4. If corrupted, manually remove directory (use caution)

**Prevention**: Check `/sdd:tasks-status` before initializing new tickets.

---

### "Planning documents too short"

**Error**:
```
❌ VALIDATION FAILED: planning/plan.md has insufficient content (45 words, need 100+)
```

**Cause**: Planning document doesn't meet minimum content requirement (100 words).

**Solution**:
1. Open the planning document in your editor
2. Add more detail:
   - Expand objectives section
   - Add deliverable descriptions
   - Include background context
3. Verify word count: `wc -w planning/plan.md`
4. Re-run `/sdd:create-tasks`

**Prevention**: Complete planning thoroughly before decomposing.

---

## Review/Decompose Issues

### "Review document missing"

**Error**:
```
✗ Review document missing (ticket-review.md)
```

**Cause**: Haven't run `/sdd:review` before attempting to execute.

**Solution**:
1. Run `/sdd:review [TICKET_ID]`
2. Address any review feedback
3. Ensure review passes
4. Then proceed with `/sdd:create-tasks` or `/sdd:do-all-tasks`

**Prevention**: Always run review after completing planning.

---

### "Review has not passed"

**Error**:
```
❌ VALIDATION FAILED: review has not passed
```

**Cause**: Review exists but returned FAIL decision.

**Solution**:
1. Read the review feedback in `planning/ticket-review.md`
2. Address each identified issue
3. Run `/sdd:update [TICKET_ID]` to fix issues
4. Re-run `/sdd:review [TICKET_ID]`
5. Repeat until review passes

**Prevention**: Address review feedback before proceeding.

---

### "Architecture document not found"

**Error**:
```
❌ planning/architecture.md - NOT FOUND (REQUIRED)
```

**Cause**: Required planning document doesn't exist.

**Solution**:
1. Create the missing file: `planning/architecture.md`
2. Add technical approach content (100+ words)
3. Include: components, integration points, dependencies
4. Re-run `/sdd:create-tasks`

**Prevention**: Use `/sdd:plan-ticket` which creates all required templates.

---

## Execution Issues

### "No tasks found"

**Error**:
```
✗ No tasks found in tasks/ directory
```

**Cause**: Attempting to execute before decomposing.

**Solution**:
1. Run `/sdd:create-tasks [TICKET_ID]` to create tasks
2. Verify tasks were created: check `tasks/` directory
3. Then run `/sdd:do-all-tasks [TICKET_ID]`

**Prevention**: Follow workflow order: review → create-tasks → execute.

---

### "Dependency check failed"

**Error**:
```
❌ DEPENDENCY CHECK FAILED: Cannot execute DEMO.2001

Unsatisfied Dependencies:
❌ DEMO.1001 - Not complete (Task completed checkbox unchecked)
```

**Cause**: Task depends on other tasks that aren't complete yet.

**Solution**:
1. Check which dependencies are blocking (shown in error)
2. Complete prerequisite tasks first: `/sdd:do-task [DEP_TASK_ID]`
3. Verify dependency shows "Task completed" checkbox checked
4. Re-run the blocked task

**Prevention**: Use `/sdd:do-all-tasks` for automatic dependency ordering.

---

### "Task file not found"

**Error**:
```
Task file not found: DEMO.1001
```

**Cause**: Task ID doesn't match any existing task file.

**Solution**:
1. List available tasks: `/sdd:tasks-status [TICKET_ID]`
2. Check task file naming in `tasks/` directory
3. Use exact task ID (case-sensitive)
4. Verify TICKET_ID prefix is correct

**Prevention**: Copy task IDs from status output.

---

## Verification Issues

### "Tests pass checkbox incorrectly checked"

**Error**:
```
❌ [CRITICAL] "Tests pass" checked but no test execution evidence found
```

**Cause**: Test checkbox marked complete without actually running tests.

**Solution**:
1. Run the appropriate test suite
2. Capture and document test output
3. Ensure all tests pass
4. Re-run verification

**Prevention**: Always run tests before marking the checkbox.

---

### "Acceptance criteria not met"

**Error**:
```
❌ VERIFICATION FAILED

Acceptance Criteria Status:
✓ Database schema created
✗ API endpoint returns user data - Issue: No endpoint implementation found
```

**Cause**: Task work incomplete or doesn't satisfy all criteria.

**Solution**:
1. Review which criteria failed (shown in error)
2. Complete missing implementation
3. Update task file checkboxes
4. Re-run verification

**Prevention**: Review all acceptance criteria before marking task complete.

---

## Archive Issues

### "Tasks not verified"

**Error**:
```
✗ DEMO_example-ticket: 2/4 tasks verified - Incomplete
  Missing verification: DEMO.1003, DEMO.1004
```

**Cause**: Attempting to archive with incomplete tasks.

**Solution**:
1. Run `/sdd:tasks-status [TICKET_ID]` to see incomplete tasks
2. Complete each incomplete task: `/sdd:do-task [TASK_ID]`
3. Ensure all tasks show "Verified" checkbox checked
4. Re-run `/sdd:archive`

**Prevention**: Complete all tasks before archiving.

---

## General Issues

### "Command not found"

**Symptom**: `/sdd:*` commands not recognized.

**Cause**: SDD plugin not installed or not loaded.

**Solution**:
1. Verify plugin installation
2. Restart Claude Code
3. Check plugin status in settings
4. Reinstall plugin if necessary

---

### "SDD_ROOT_DIR not set"

**Symptom**: Commands fail with directory errors.

**Cause**: Environment variable not configured.

**Solution**:
1. The plugin should set this automatically via SessionStart hook
2. If not set, verify hook is running
3. Manual override: `export SDD_ROOT_DIR=/app/.sdd`
4. Run `/sdd:setup` to verify environment

---

### "Git operations fail"

**Symptom**: Commit or archive fails with git errors.

**Cause**: Git not configured or not in repository.

**Solution**:
1. Verify git repository: `git status`
2. Configure git if needed:
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "your@email.com"
   ```
3. Initialize repository if needed: `git init`

---

## Recovery Procedures

### Recover from Failed Decompose

If decompose created partial tasks and then failed:

1. Review tasks created in `tasks/` directory
2. Delete any incomplete/corrupted task files
3. Fix the planning issues that caused failure
4. Re-run `/sdd:create-tasks` (won't overwrite existing valid tasks)

### Recover from Failed Task Execution

If task execution fails mid-work:

1. Review task file to see what was completed
2. Check `git status` for uncommitted changes
3. Decide: continue task or restart
4. Update task checkboxes to reflect actual state
5. Re-run `/sdd:do-task` to resume

### Recover from Corrupted Ticket

If ticket directory is corrupted:

1. Back up the ticket directory
2. Review what's salvageable (planning, tasks, commits)
3. If planning intact: Continue from last checkpoint
4. If planning lost: Recover from git history
5. If unrecoverable: Start new ticket, reference old work in notes

---

## Loop Controller Issues

This section covers issues specific to autonomous loop execution via `sdd-loop.sh`.
For detailed safety feature documentation, see the [Safety Guidelines](./safety-guidelines.md).

### Loop Stops Immediately

**Symptoms**:
- Loop exits with "No more work available" after first iteration
- Message shows "reason: no tasks remaining" or similar
- Zero tasks were executed

**Cause**: No agent-ready tasks are available for autonomous execution. This can happen when:
- No tasks have been created yet (`/sdd:create-tasks` not run)
- All tasks are already completed
- Tasks exist but `.autogate.json` blocks autonomous execution
- Tasks have unmet dependencies that prevent execution

**Solution**:
1. Check task status: `/sdd:tasks-status [TICKET_ID]`
2. Verify tasks exist in `tasks/` directory
3. Check `.autogate.json` configuration:
   ```bash
   cat _SDD/tickets/TICKET_name/.autogate.json
   ```
4. Ensure both `ready` and `agent_ready` are `true`:
   ```json
   {"ready": true, "agent_ready": true}
   ```
5. Check for dependency blocks - prerequisite tasks must be complete

**Prevention**: Always verify task status and `.autogate.json` configuration before starting the loop. Run `/sdd:tasks-status` to confirm agent-ready tasks exist.

---

### Task Times Out

**Symptoms**:
- Task execution stopped mid-work
- Log shows timeout-related termination
- Claude process killed after extended execution

**Cause**: Task execution exceeded the configured timeout limit (default: 3600 seconds / 1 hour). Complex tasks involving large file operations, extensive testing, or external API calls may exceed this limit.

**Solution**:
1. Review the task complexity - is it too large for a single task?
2. Increase timeout for complex tasks:
   ```bash
   ./sdd-loop.sh --timeout 7200 /workspace/repos/  # 2 hours
   ```
3. Or set via environment variable:
   ```bash
   export SDD_LOOP_TIMEOUT=7200
   ./sdd-loop.sh /workspace/repos/
   ```
4. Check if the task is stuck (infinite loop, waiting for input)
5. Review Claude execution logs for clues about why it ran long

**Prevention**:
- Break large tasks into smaller, focused units (aim for under 30 minutes each)
- Set appropriate timeouts based on expected task complexity
- Use phase boundaries to create natural checkpoints

See [Safety Guidelines > Configuration for Safety](./safety-guidelines.md#4-configuration-for-safety) for timeout configuration details.

---

### Max Iterations Reached

**Symptoms**:
- Log message: "Reached maximum iterations (50)"
- Loop stops with exit code 1
- Tasks may still be pending

**Cause**: The loop executed 50 iterations (default limit) without completing all work. This typically indicates:
- Large backlog of tasks (legitimate, but consider phased execution)
- Tasks are being re-queued without completing
- Circular dependency or stuck task pattern

**Solution**:
1. Review progress - are tasks actually completing?
   ```bash
   ./master-status-board.sh /workspace/repos/ | jq '.repos[].tickets'
   ```
2. If legitimate large workload, increase the limit:
   ```bash
   ./sdd-loop.sh --max-iterations 100 /workspace/repos/
   ```
3. Check for stuck tasks that keep failing and retrying
4. Resume the loop if more work remains:
   ```bash
   ./sdd-loop.sh --verbose /workspace/repos/
   ```

**Prevention**:
- Use phase boundaries (`stop_at_phase` in `.autogate.json`) for staged execution
- Break large tickets into multiple smaller tickets
- Monitor progress periodically for long-running sessions

See [Safety Guidelines > Error Limits](./safety-guidelines.md#33-error-limits) for iteration limit configuration.

---

### Consecutive Error Limit Reached

**Symptoms**:
- Log message: "Reached maximum consecutive errors (3)"
- Loop aborts with exit code 1
- Same or similar tasks failing repeatedly

**Cause**: Three consecutive task executions failed. This safety feature prevents runaway failure loops that waste resources. Common causes:
- Task definition has errors (missing files, bad acceptance criteria)
- Environment issue (missing dependencies, permission problems)
- External service unavailable
- Task prerequisites not met

**Solution**:
1. Identify the failing task from logs:
   ```bash
   ./master-status-board.sh /workspace/repos/ | jq '.recommended_action'
   ```
2. Review the task definition for issues
3. Check prerequisites are satisfied
4. Fix the underlying problem before retrying
5. Resume the loop:
   ```bash
   ./sdd-loop.sh --verbose /workspace/repos/
   ```

**Prevention**:
- Test tasks manually before autonomous execution
- Ensure task acceptance criteria are clear and achievable
- Verify environment dependencies are available
- Use dry-run mode first: `./sdd-loop.sh --dry-run`

Note: The consecutive error counter resets to zero after each successful task, allowing recovery from occasional failures.

See [Safety Guidelines > Error Limits](./safety-guidelines.md#33-error-limits) for error limit configuration.

---

### Circuit Breaker Warnings

**Symptoms**:
- Log warning: "Circuit breaker: Long-running loop detected (iteration 25)"
- Log warning: "Circuit breaker: Extended loop execution (iteration 40)"
- Loop continues executing (warnings are advisory only)

**Cause**: The loop has been running for an extended number of iterations. These are advisory warnings, not errors:
- **Iteration 25**: Indicates loop is running longer than typical
- **Iteration 40**: Approaching default max_iterations (50)

The circuit breaker is intentionally advisory-only to avoid aborting productive work.

**Solution**:
1. Review loop progress - is work being completed?
2. Check if tasks are completing or repeatedly failing
3. Consider whether to intervene:
   - Continue if making good progress
   - Stop (`Ctrl+C`) if stuck or problematic
4. Review metrics after completion:
   ```bash
   cat /tmp/metrics.json | jq '.circuit_breaker'
   ```

**Prevention**:
- Use phase boundaries for natural checkpoints
- Set appropriate `--max-iterations` based on expected workload
- Monitor long-running loops periodically

See [Safety Guidelines > Circuit Breaker](./safety-guidelines.md#31-circuit-breaker-advisory-warnings) for detailed circuit breaker documentation.

---

### Claude CLI Not Found

**Symptoms**:
- Error: "claude CLI not found"
- Recommendation to install from https://claude.ai/download
- Task execution fails before starting

**Cause**: The Claude Code CLI is not installed or not in the system PATH. The loop controller requires Claude Code to execute tasks.

**Solution**:
1. Verify Claude is installed:
   ```bash
   claude --version
   ```
2. If not installed, install Claude Code:
   - Visit https://claude.ai/download
   - Follow installation instructions for your platform
3. If installed but not found, check PATH:
   ```bash
   command -v claude
   echo $PATH
   ```
4. Add Claude to PATH if necessary:
   ```bash
   export PATH="$PATH:/path/to/claude/bin"
   ```
5. Restart your shell or source your profile:
   ```bash
   source ~/.bashrc  # or ~/.zshrc
   ```

**Prevention**:
- Install Claude Code before using the loop controller
- Verify installation with `claude --version` before starting loops
- Ensure Claude is in PATH for the user running the loop

---

### Permission Errors

**Symptoms**:
- Errors about "Permission denied" or "Cannot write"
- Failed to create or modify files in workspace
- Task execution fails with file operation errors

**Cause**: The loop controller or Claude process lacks permissions to read/write required directories. Common causes:
- Running as wrong user
- Workspace owned by different user
- Read-only filesystem or directory
- Docker volume permission issues

**Solution**:
1. Check workspace ownership:
   ```bash
   ls -la _SDD/
   ls -la _SDD/tickets/
   ```
2. Verify current user:
   ```bash
   whoami
   id
   ```
3. Fix ownership if needed:
   ```bash
   sudo chown -R $(whoami):$(whoami) _SDD/
   ```
4. Check directory permissions:
   ```bash
   ls -ld _SDD/tickets/TICKET_name/
   ```
5. Ensure write permissions:
   ```bash
   chmod u+w _SDD/tickets/TICKET_name/
   ```

**Prevention**:
- Run the loop as the user who owns the workspace
- Ensure workspace directories are writable before starting
- In Docker, verify volume mounts have correct permissions
- Check containerized environments for UID/GID mapping issues

---

### Task Execution Fails Silently

**Symptoms**:
- Task marked as failed but no clear error message
- Claude exited without completing work
- Incomplete changes in workspace

**Cause**: Claude execution ended unexpectedly without explicit error output. Possible causes:
- Memory limits exceeded
- Signal interruption
- Network disconnection (for API-based Claude)
- Task instructions unclear or malformed

**Solution**:
1. Enable verbose logging for more details:
   ```bash
   ./sdd-loop.sh --verbose /workspace/repos/
   ```
2. Enable debug mode for maximum detail:
   ```bash
   ./sdd-loop.sh --debug /workspace/repos/
   ```
3. Check workspace state:
   ```bash
   git status
   git diff
   ```
4. Review the task definition for issues
5. Try executing the task manually:
   ```bash
   claude "/sdd:do-task TASK_ID"
   ```

**Prevention**:
- Use verbose mode for better visibility
- Write clear, specific task acceptance criteria
- Keep tasks focused and reasonably scoped
- Monitor system resources during execution

---

### .autogate.json Parse Errors

**Symptoms**:
- Error parsing `.autogate.json`
- Unexpected loop behavior (skipping tasks, not respecting phase boundaries)
- JSON syntax error messages

**Cause**: The `.autogate.json` file contains invalid JSON syntax. Common mistakes:
- Trailing commas
- Missing quotes around strings
- Using single quotes instead of double quotes
- Comments in JSON (not allowed)

**Solution**:
1. Validate the JSON file:
   ```bash
   cat _SDD/tickets/TICKET_name/.autogate.json | jq .
   ```
2. Fix any syntax errors
3. Ensure proper format:
   ```json
   {"ready": true, "agent_ready": true, "stop_at_phase": 2}
   ```
4. Recreate the file if corrupted:
   ```bash
   echo '{"ready": true, "agent_ready": true}' > _SDD/tickets/TICKET_name/.autogate.json
   ```

**Prevention**:
- Use a JSON validator when editing `.autogate.json`
- Copy from template rather than typing manually
- Test with `jq .` after any edits

---

## Getting Help

### Self-Service Resources

- [Getting Started](getting-started.md) - Workflow walkthrough
- [Command Reference](command-reference.md) - Detailed command docs
- [Workflow Guide](workflow-guide.md) - Visual workflow
- [Quality Assurance](../skills/project-workflow/references/quality-assurance.md) - Quality gates

### When to Escalate

- Error messages not in this guide
- Repeated failures after following troubleshooting
- Plugin crashes or hangs
- Data corruption or loss

### How to Report Issues

1. Document exact error message
2. Capture command that caused error
3. Note which workflow phase you're in
4. Describe steps to reproduce
5. Report to plugin maintainers with details

---

**Document Version**: 1.0
**Applies to**: SDD Plugin v1.0.0+
