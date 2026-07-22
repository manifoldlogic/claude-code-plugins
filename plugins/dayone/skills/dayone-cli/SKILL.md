---
name: dayone-cli
description: Manage a Day One personal journal from Claude Code — create and organize journal entries (text, tags, dates, journals, photos, location, starred) using the Day One `dayone` CLI on the macOS host. Use when the user wants to write, log, or add to their Day One journal, review how journaling works, or set up / install the Day One CLI. Handles first-run detection and opt-in installation of the CLI.
---

# Day One CLI

Create and manage entries in the user's [Day One](https://dayoneapp.com/) journal
from Claude Code. Day One's `dayone` CLI ships with the Day One **macOS app** and
runs **only on macOS**. All journal operations go through the helper script
`scripts/dayone-host.sh`, which runs the CLI locally when you are on the host, or
over SSH to `host.docker.internal` when you are in a Linux devcontainer.

> Assume `DO="${CLAUDE_PLUGIN_ROOT}/skills/dayone-cli/scripts/dayone-host.sh"` in
> the commands below. Run `chmod +x "$DO"` once if needed.

## Before anything else: verify the CLI (first run)

The very first time in a session that the user asks to journal, run a health check
**before** attempting to write:

```bash
"$DO" check
```

Interpret the exit status:

- **0** — CLI installed and working. Proceed with the requested operation.
- **10** — Day One app is present but the CLI is not installed yet. **Do not
  install automatically.** Follow the opt-in installation flow below.
- **11** — The Day One macOS app is not installed. Tell the user to install Day
  One from the Mac App Store and open it once; you cannot do this for them.
- **4** — The host is unreachable over SSH. Help the user enable Remote Login
  (System Settings → General → Sharing → Remote Login) and confirm
  `ssh <user>@host.docker.internal` works with a key. The SSH user defaults to
  the container-wide `HOST_USER` (falling back to `$USER`); set `DAYONE_HOST_USER`
  to override if the host username differs.

## Installation is opt-in — never silent

Even though the wrapper can perform the install itself, installing the CLI
modifies the user's macOS system and needs their `sudo` password. **Always ask
first.** When `check` returns 10:

1. Explain in one or two sentences: the Day One CLI isn't installed yet; you can
   install it by running the installer that ships inside the Day One app, which
   requires their macOS login password.
2. Show the exact command that will run:
   `sudo bash "/Applications/Day One.app/Contents/Resources/install_cli.sh"`
3. Offer both paths and let the user choose:
   - **You run it for them** (they consent): `"$DO" install --yes`
     The `sudo` password prompt appears in their terminal over an interactive
     SSH session; they type it themselves — you never see or handle it.
   - **They run it themselves** on the host, then you re-run `"$DO" check`.
4. Only invoke `"$DO" install --yes` **after** the user explicitly agrees. Never
   pass `--yes` on your own initiative. The script also refuses to install
   without `--yes` as a backstop.

After a successful install, `install` re-runs `check` automatically; confirm you
see `[OK]` before continuing.

## Creating entries

The CLI's one write command is `dayone new`. The wrapper sends entry text over
stdin so quotes, newlines, and unicode are preserved. Pass Day One flags through
after `new`'s inputs.

```bash
# Simplest entry (text via stdin):
printf '%s' "Today I shipped the Day One plugin." | "$DO" new

# Multi-line body:
"$DO" new <<'ENTRY'
Morning pages.

Three things I'm grateful for today...
ENTRY

# With tags, a specific journal, and starred:
printf '%s' "Team offsite recap" | "$DO" new --journal "Work" --tags offsite planning --starred

# Backdated entry (see reference for date formats):
printf '%s' "Backfilled note" | "$DO" new --date "2026-07-01 09:30:00"

# Attach photos (max 10 files); note the trailing `--` handling:
"$DO" raw --attachments ~/Pictures/a.jpg ~/Pictures/b.jpg -- new "Trip photos"
```

Key options (full list in `references/cli-reference.md`): `--journal <name>`,
`--tags <t1> <t2> …`, `--date` / `--isoDate` / `--all-day`, `--starred`,
`--coordinate <lat> <lon>`, `--time-zone <IANA>`, `--attachments <files> --`.

Rules of thumb:
- The target `--journal` must already exist in Day One; the CLI won't create it.
- Attachment paths are resolved **on the macOS host**, not in the container.
- Confirm the entry text with the user before writing when they dictated
  something long or ambiguous — journal entries are the user's personal record.

## Reference

`references/cli-reference.md` — full command and option reference, date/time
formats, exit codes from the wrapper, and troubleshooting (SSH, sudo, deprecated
`dayone2`).

## Scope and limits

- **macOS + Day One app required.** There is no Linux/Windows Day One CLI.
- The CLI supports creating entries (`new`) only — it cannot read, search, edit,
  or delete existing entries. Don't promise retrieval features.
- Never fabricate journal content. Write only what the user provides or approves.
