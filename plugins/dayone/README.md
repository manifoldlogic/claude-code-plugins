# Day One Plugin

## Overview

The Day One plugin lets you manage a personal [Day One](https://dayoneapp.com/)
journal from within Claude Code, powered by the official Day One `dayone`
command-line tool. Ask Claude to write a journal entry, log the day, add tags or
photos, or backdate a note, and it drives the CLI for you. When Claude Code runs
inside a Linux devcontainer, the plugin executes the CLI on your macOS host over
SSH; when run directly on macOS it uses the CLI locally.

### Key Features

- **Entry creation** — write text entries, from a one-liner to multi-line prose.
- **Organization** — assign tags, target a specific journal, star entries.
- **Dating** — set a custom date/time, ISO date, all-day, or timezone.
- **Attachments** — add photos, videos, audio, or PDFs (up to 10 per entry).
- **Location** — attach coordinates to an entry.
- **Guided, opt-in setup** — Claude checks whether the CLI is installed and, only
  with your explicit consent, installs it for you from the Day One app bundle.

## Prerequisites

The Day One CLI is **macOS-only** and ships with the Day One Mac app.

### 1. Day One macOS app

Install Day One from the Mac App Store and **open it at least once** (sign in so a
local journal exists). The CLI installer lives inside the app bundle.

### 2. Host access from a devcontainer (only if you run Claude Code in a container)

The plugin reaches the macOS host over SSH at `host.docker.internal`:

- Enable **Remote Login**: System Settings → General → Sharing → Remote Login.
- Confirm key-based SSH works: `ssh <your-mac-username>@host.docker.internal`.
- If your Mac username differs from the container's `$USER`, set
  `DAYONE_HOST_USER=<your-mac-username>` in the environment.

Running Claude Code directly on macOS needs none of this — the plugin detects the
host and runs the CLI locally.

## Installation of the CLI (opt-in)

You don't install the CLI up front. The first time you ask to journal, Claude runs
a health check. If the CLI isn't installed yet, Claude explains what it will do
and asks permission before running the installer:

```bash
sudo bash "/Applications/Day One.app/Contents/Resources/install_cli.sh"
```

This needs your macOS login password, which you type yourself — Claude never
handles it. You can also let Claude run it for you (`dayone-host.sh install --yes`)
or run it manually and have Claude re-check. Installation never happens silently.

## Usage

Just ask, in natural language:

- "Add a Day One entry: shipped the plugin today, tag it work and dev."
- "Journal this as a starred entry in my Personal journal."
- "Backdate a note to last Monday morning about the offsite."
- "Is the Day One CLI set up? If not, help me install it."

Under the hood Claude uses the `dayone-cli` skill and the helper script
`skills/dayone-cli/scripts/dayone-host.sh`. See
`skills/dayone-cli/references/cli-reference.md` for the full command reference,
wrapper exit codes, environment variables, and troubleshooting.

## Limitations

- Requires macOS and the Day One app; there is no Linux/Windows CLI.
- The CLI can **create** entries only — it cannot read, search, edit, or delete
  existing entries.
- The target journal must already exist in Day One; the CLI won't create it.
