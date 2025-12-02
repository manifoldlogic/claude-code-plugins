# GitHub Actions Plugin

GitHub Actions workflow management with specialized agent and gh CLI skill.

## Overview

The GitHub Actions plugin provides comprehensive CI/CD pipeline management for GitHub repositories. It includes:

- **Workflow Creation** - Design and implement GitHub Actions workflows
- **Optimization** - Improve workflow performance and reliability
- **Troubleshooting** - Debug failed workflows and jobs
- **Matrix Builds** - Configure multi-platform and multi-version testing
- **Secrets Management** - Handle sensitive data securely
- **gh CLI Skill** - GitHub CLI commands for workflow management

## Installation

### Prerequisites

1. **GitHub CLI (`gh`)**
   - Install: `brew install gh` (macOS) or [GitHub CLI installation](https://cli.github.com/)
   - Authenticate: `gh auth login`

2. **GitHub Repository**
   - Repository with Actions enabled
   - Appropriate permissions for workflow management

### Install Plugin

```bash
# Add marketplace (if not already added)
/plugin marketplace add /workspace/.crewchief/claude-code-plugins

# Install github-actions plugin
/plugin install github-actions@crewchief
```

After installation, restart Claude Code to activate the plugin.

## Components

### Specialized Agent

#### `github-actions-specialist`

Expert agent for GitHub Actions workflows with capabilities:

**Workflow Creation:**
- Design CI/CD pipelines for any tech stack
- Configure workflow triggers (push, pull_request, schedule, etc.)
- Set up matrix builds for multi-platform testing
- Implement caching strategies for dependencies

**Optimization:**
- Reduce workflow runtime
- Implement parallel job execution
- Configure artifact caching
- Optimize Docker layer caching

**Troubleshooting:**
- Debug workflow failures
- Analyze job logs
- Fix syntax errors in YAML
- Resolve permission issues

**Security:**
- Manage secrets and environment variables
- Configure OIDC for cloud deployments
- Implement least-privilege permissions
- Audit workflow security

**Example Usage:**
```
@github-actions-specialist Create a CI workflow for a TypeScript project that runs tests and builds on Node 18 and 20
```

### gh CLI Skill

The `gh-cli` skill provides guidance for using the GitHub CLI to manage workflows.

**Authentication Check:**

Before using any gh commands, always verify authentication:

```bash
gh auth status
```

If not authenticated, run `gh auth login` first.

**Common Commands:**

```bash
# List workflows
gh workflow list

# List recent workflow runs
gh run list

# View run details and logs
gh run view <run-id> --log-failed

# Trigger a workflow
gh workflow run <workflow-name>

# Rerun failed jobs
gh run rerun <run-id> --failed

# View PR checks
gh pr checks
```

See `skills/gh-cli/SKILL.md` for complete documentation.

## Quick Start

### Create Your First Workflow

1. **Ask the specialist to create a workflow:**
   ```
   @github-actions-specialist Create a Node.js CI workflow that:
   - Runs tests on Node 18 and 20
   - Caches npm dependencies
   - Uploads coverage reports
   - Runs on every push and PR
   ```

2. **The agent will:**
   - Create `.github/workflows/ci.yml`
   - Configure jobs, steps, and caching
   - Add appropriate triggers
   - Include best practices

3. **Commit and push:**
   ```bash
   git add .github/workflows/ci.yml
   git commit -m "ci: add Node.js CI workflow"
   git push
   ```

### Troubleshoot a Failed Workflow

1. **Check gh CLI authentication:**
   ```bash
   gh auth status
   ```

2. **List failed runs:**
   ```bash
   gh run list --status=failure
   ```

3. **View failed job logs:**
   ```bash
   gh run view <run-id> --log-failed
   ```

4. **Ask the specialist to fix:**
   ```
   @github-actions-specialist Fix the workflow based on this error: [paste error]
   ```

### Optimize Existing Workflows

1. **Request optimization:**
   ```
   @github-actions-specialist Optimize the ci.yml workflow to reduce runtime
   ```

2. **The agent will:**
   - Analyze current workflow structure
   - Identify bottlenecks
   - Suggest parallelization opportunities
   - Implement caching strategies
   - Update workflow file

## Common Use Cases

### CI/CD for Different Stacks

**Node.js/TypeScript:**
```yaml
- Lint, test, build on multiple Node versions
- Upload coverage to Codecov
- Publish to npm registry
```

**Python:**
```yaml
- Test on multiple Python versions
- Run pytest with coverage
- Build and publish to PyPI
```

**Rust:**
```yaml
- Build and test with cargo
- Cross-compile for multiple platforms
- Cache cargo dependencies
```

**Docker:**
```yaml
- Build multi-arch images
- Push to Docker Hub or GHCR
- Scan for vulnerabilities
```

### Matrix Builds

Configure testing across multiple dimensions:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest, windows-latest]
    node: [18, 20]
```

### Caching Strategies

Improve workflow speed with caching:

```yaml
- uses: actions/cache@v3
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
```

### Secrets Management

Secure handling of sensitive data:

```yaml
env:
  API_KEY: ${{ secrets.API_KEY }}
```

## Best Practices

### Workflow Design
- Keep workflows simple and focused
- Use reusable workflows for common patterns
- Implement proper error handling
- Add meaningful job and step names

### Performance
- Cache dependencies aggressively
- Run jobs in parallel when possible
- Use appropriate runner types (ubuntu, macos, windows)
- Implement conditional job execution

### Security
- Never commit secrets to repository
- Use GITHUB_TOKEN for API access
- Implement least-privilege permissions
- Audit third-party actions

### Reliability
- Add timeout limits to jobs
- Implement retry logic for flaky tests
- Use matrix builds for cross-platform testing
- Monitor workflow run times

## Troubleshooting

### gh CLI not authenticated
```
ERROR: GitHub CLI is not authenticated
```
**Solution:** Run `gh auth login` and follow the prompts.

### Workflow not triggering
- Check workflow triggers in YAML
- Verify branch/path filters
- Ensure workflow file is in `.github/workflows/`
- Check repository permissions

### Job failing
- Review job logs via `gh run view <id> --log-failed`
- Check action versions
- Verify secrets are configured
- Test steps locally when possible

### Performance issues
- Enable caching for dependencies
- Reduce job concurrency if hitting limits
- Use self-hosted runners for private repos
- Optimize Docker builds with layer caching

### Permission errors
- Check GITHUB_TOKEN permissions
- Verify repository settings
- Add required permissions to workflow
- Check organization security policies

## Configuration

### Environment Variables

```bash
# GitHub CLI authentication (handled by gh auth login)
GH_TOKEN=<your-github-token>
```

## Version

Current version: **0.1.0**

## Keywords

`github-actions`, `ci-cd`, `workflows`, `automation`, `gh-cli`, `github`

## Links

- [Repository](https://github.com/manifoldlogic/claude-code-plugins)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub CLI Documentation](https://cli.github.com/manual/)

## Examples

### Basic CI Workflow

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm test
      - run: npm run build
```

### Matrix Build

```yaml
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        node: [18, 20]
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: ${{ matrix.node }}
      - run: npm ci
      - run: npm test
```

### Docker Build and Push

```yaml
jobs:
  docker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: docker/setup-buildx-action@v2
      - uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v4
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```
