#!/usr/bin/env bash
# Check if GitHub CLI is authenticated
# Exit 0 if authenticated, exit 1 if not

set -euo pipefail

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "ERROR: GitHub CLI (gh) is not installed"
    echo "Install it with: brew install gh (macOS) or see https://cli.github.com/"
    exit 1
fi

# Check authentication status
if gh auth status &> /dev/null; then
    echo "GitHub CLI is authenticated"
    gh auth status
    exit 0
else
    echo "ERROR: GitHub CLI is not authenticated"
    echo "Please run: gh auth login"
    exit 1
fi
