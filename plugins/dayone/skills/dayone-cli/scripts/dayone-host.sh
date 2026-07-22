#!/usr/bin/env bash
#
# dayone-host.sh — invoke the Day One CLI (`dayone`) on the macOS host.
#
# The Day One CLI ships only with the Day One macOS app and runs only on macOS.
# When Claude Code runs inside a Linux devcontainer, this wrapper reaches the
# macOS host over SSH (host.docker.internal). When run directly on the host it
# invokes `dayone` locally. Follows the repo's base64-over-SSH convention so
# entry text with quotes/newlines/unicode survives transport untouched.
#
# Subcommands:
#   check              Report whether the Day One app + `dayone` CLI are usable.
#   install [--yes]    Install the `dayone` CLI from the Day One app bundle.
#                      Requires sudo on the host (interactive password). Opt-in:
#                      refuses to run without --yes.
#   new [dayone-args]  Create a journal entry. Entry text is read from stdin and
#                      transported safely; extra flags (--journal, --tags, ...)
#                      are passed through to `dayone new`.
#   raw  [dayone-args] Pass arguments straight through to `dayone` (advanced).
#   version            Print the host `dayone` version.
#
# Environment:
#   DAYONE_HOST_USER   macOS host username for SSH (default: $USER).
#   DAYONE_HOST        SSH host (default: host.docker.internal).
#   DAYONE_SSH_OPTS    Extra ssh options (default: -o BatchMode=yes for non-tty).
#   DAYONE_FORCE_MODE  "local" or "remote" to override auto-detection.

set -euo pipefail

HOST_USER="${DAYONE_HOST_USER:-${USER:-}}"
HOST="${DAYONE_HOST:-host.docker.internal}"
APP_CLI_INSTALLER="/Applications/Day One.app/Contents/Resources/install_cli.sh"

info() { printf '%s\n' "$*" >&2; }
ok()   { printf '[OK] %s\n' "$*" >&2; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; }

# ----------------------------------------------------------------------------
# Mode detection: run `dayone` locally (on the host) or remotely (over SSH)?
# ----------------------------------------------------------------------------
detect_mode() {
  if [[ -n "${DAYONE_FORCE_MODE:-}" ]]; then
    printf '%s' "$DAYONE_FORCE_MODE"; return
  fi
  # On macOS directly, or where `dayone` is already on PATH, run locally.
  if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]] || command -v dayone >/dev/null 2>&1; then
    printf 'local'
  else
    printf 'remote'
  fi
}

require_host_user() {
  if [[ -z "$HOST_USER" ]]; then
    err "No host user set. Export DAYONE_HOST_USER=<your-macos-username>."
    exit 3
  fi
}

# Run a shell snippet on the host (local: eval; remote: over SSH).
# Usage: run_on_host <tty:0|1> <shell-snippet>
run_on_host() {
  local want_tty="$1"; shift
  local snippet="$1"
  local mode; mode="$(detect_mode)"
  if [[ "$mode" == "local" ]]; then
    bash -c "$snippet"
  else
    require_host_user
    local ssh_opts="${DAYONE_SSH_OPTS:-}"
    if [[ "$want_tty" == "1" ]]; then
      # Interactive (sudo password prompt) — allocate a TTY, allow prompts.
      # shellcheck disable=SC2086
      ssh -t $ssh_opts "${HOST_USER}@${HOST}" "$snippet"
    else
      # Non-interactive; fail fast rather than hang on a password prompt.
      ssh_opts="${ssh_opts:--o BatchMode=yes}"
      # shellcheck disable=SC2086
      ssh $ssh_opts "${HOST_USER}@${HOST}" "$snippet"
    fi
  fi
}

# ----------------------------------------------------------------------------
# check — is the CLI usable?
# ----------------------------------------------------------------------------
cmd_check() {
  local mode; mode="$(detect_mode)"
  info "Mode: $mode (host: ${HOST_USER:-?}@${HOST})"

  # 1) Can we reach the host at all (remote mode only)?
  if [[ "$mode" == "remote" ]]; then
    if ! run_on_host 0 'true' >/dev/null 2>&1; then
      err "Cannot reach the macOS host over SSH (${HOST_USER}@${HOST})."
      err "Ensure Remote Login is on (System Settings > General > Sharing)"
      err "and that key-based SSH to the host works: ssh ${HOST_USER}@${HOST}"
      return 4
    fi
  fi

  # 2) Is the `dayone` CLI present?
  if run_on_host 0 'command -v dayone >/dev/null 2>&1'; then
    local ver; ver="$(run_on_host 0 'dayone --version 2>/dev/null || true')"
    ok "Day One CLI is installed. Version: ${ver:-unknown}"
    return 0
  fi

  warn "Day One CLI (dayone) is NOT installed on the host."
  # 3) Distinguish "app missing" from "CLI not installed yet".
  if run_on_host 0 "test -e \"$APP_CLI_INSTALLER\""; then
    info "The Day One app IS installed and ships the CLI installer."
    info "Run:  dayone-host.sh install --yes   (asks for your macOS password)"
    return 10   # app present, CLI installable
  else
    err "The Day One macOS app was not found at /Applications/Day One.app."
    err "Install Day One from the Mac App Store and open it once, then re-run check."
    return 11   # app missing
  fi
}

# ----------------------------------------------------------------------------
# install — opt-in; runs the app-bundle installer with sudo on the host.
# ----------------------------------------------------------------------------
cmd_install() {
  local yes=0
  for a in "$@"; do [[ "$a" == "--yes" || "$a" == "-y" ]] && yes=1; done
  if [[ "$yes" -ne 1 ]]; then
    err "Refusing to install without explicit consent."
    err "This runs:  sudo bash \"$APP_CLI_INSTALLER\""
    err "on the macOS host and will prompt for your login password."
    err "Re-run with --yes to proceed."
    return 2
  fi
  if ! run_on_host 0 "test -e \"$APP_CLI_INSTALLER\""; then
    err "Installer not found at $APP_CLI_INSTALLER."
    err "Install the Day One app from the Mac App Store and open it once first."
    return 11
  fi
  info "Installing the Day One CLI on the host (sudo password may be required)..."
  # TTY required so sudo can prompt for the password interactively.
  run_on_host 1 "sudo bash \"$APP_CLI_INSTALLER\""
  info "Verifying..."
  cmd_check
}

# ----------------------------------------------------------------------------
# new — create an entry. Text on stdin, base64-transported. Flags passed through.
# ----------------------------------------------------------------------------
cmd_new() {
  local payload_b64=""
  if [[ ! -t 0 ]]; then
    payload_b64="$(base64 | tr -d '\n')"
  fi
  # Build the remote command. Extra args (e.g. --journal X --tags a b) pass through.
  local passthru=""
  for a in "$@"; do passthru+=" $(printf '%q' "$a")"; done

  if [[ -n "$payload_b64" ]]; then
    run_on_host 0 "printf '%s' '$payload_b64' | base64 -d | dayone${passthru} new"
  else
    # No stdin text — args must carry the entry (e.g. via -- new \"text\").
    run_on_host 0 "dayone${passthru}"
  fi
}

cmd_raw()     { local p=""; for a in "$@"; do p+=" $(printf '%q' "$a")"; done; run_on_host 0 "dayone${p}"; }
cmd_version() { run_on_host 0 'dayone --version'; }

main() {
  local sub="${1:-check}"; shift || true
  case "$sub" in
    check)   cmd_check "$@" ;;
    install) cmd_install "$@" ;;
    new)     cmd_new "$@" ;;
    raw)     cmd_raw "$@" ;;
    version) cmd_version "$@" ;;
    -h|--help|help)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) err "Unknown subcommand: $sub"; err "Try: check | install | new | raw | version"; exit 64 ;;
  esac
}
main "$@"
