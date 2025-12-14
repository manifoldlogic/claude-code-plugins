#!/usr/bin/env bash
#
# demo_config_usage.sh - Demonstration of configuration system usage
#
# Shows how to load configuration, access values, and use overrides
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source the common library
# shellcheck source=../lib/common.sh
source "${LIB_DIR}/common.sh"

echo "==================================="
echo "Configuration System Demo"
echo "==================================="
echo ""

# Load configuration
echo "Step 1: Loading configuration..."
if ! load_config; then
    echo "ERROR: Failed to load configuration"
    exit 2
fi
echo "SUCCESS: Configuration loaded"
echo ""

# Display configuration values
echo "Step 2: Displaying configuration values:"
echo "  SDD Root:              $CONFIG_SDD_ROOT"
echo "  Max Retry Attempts:    $CONFIG_RETRY_MAX_ATTEMPTS"
echo "  Initial Retry Delay:   ${CONFIG_RETRY_INITIAL_DELAY}s"
echo "  Backoff Multiplier:    ${CONFIG_RETRY_BACKOFF_MULTIPLIER}x"
echo "  Checkpoint Frequency:  $CONFIG_CHECKPOINT_FREQUENCY"
echo "  Max Checkpoints:       $CONFIG_CHECKPOINT_MAX"
echo "  Risk Tolerance:        $CONFIG_RISK_TOLERANCE"
echo "  Decision Timeout:      ${CONFIG_DECISION_TIMEOUT}s"
echo "  Log Level:             $CONFIG_LOG_LEVEL"
echo "  Log Format:            $CONFIG_LOG_FORMAT"
echo "  Claude Path:           $CONFIG_CLAUDE_PATH"
echo "  Jira CLI Path:         $CONFIG_JIRA_PATH"
echo "  GitHub CLI Path:       $CONFIG_GH_PATH"
echo ""

# Demonstrate environment override
echo "Step 3: Testing environment override..."
echo "  Setting SDD_LOG_LEVEL=debug"
export SDD_LOG_LEVEL=debug

# Reload config to apply override
if ! load_config 2>/dev/null; then
    echo "ERROR: Failed to reload configuration"
    exit 2
fi

echo "  New log level: $CONFIG_LOG_LEVEL"
echo ""

# Show log level filtering in action
echo "Step 4: Testing log level filtering (now set to debug):"
log_debug "This is a debug message (should be visible)"
log_info "This is an info message (should be visible)"
log_warn "This is a warning message (should be visible)"
echo ""

# Demonstrate validation
echo "Step 5: Testing configuration validation..."
echo "  All validations passed during load_config"
echo ""

# Show usage in a typical script
echo "Step 6: Example usage in automation script:"
cat <<'EOF'
  #!/usr/bin/env bash
  set -euo pipefail
  source "$(dirname "$0")/../lib/common.sh"

  # Load config at script start
  load_config || exit 2

  # Use config values
  max_attempts=$CONFIG_RETRY_MAX_ATTEMPTS
  for ((i=1; i<=max_attempts; i++)); do
      if perform_operation; then
          break
      fi
      log_warn "Attempt $i failed, retrying..."
      sleep $CONFIG_RETRY_INITIAL_DELAY
  done
EOF
echo ""

echo "==================================="
echo "Demo Complete!"
echo "==================================="
