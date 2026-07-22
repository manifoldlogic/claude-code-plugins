# Day One CLI Reference

Full reference for the Day One `dayone` command line tool and the
`dayone-host.sh` wrapper used by this plugin.

Source: https://dayoneapp.com/guides/tips-and-tutorials/command-line-interface-cli/

## Requirements

- **macOS only.** The CLI ships inside the Day One macOS app; there is no Linux
  or Windows build.
- The **Day One app must be installed and launched at least once** before the CLI
  works (Day One Mac 2.1.2+ for the installer; `dayone` command as of Day One Mac
  2025.19, which deprecated the older `dayone2`).

## Installing the CLI (on the macOS host)

```bash
sudo bash "/Applications/Day One.app/Contents/Resources/install_cli.sh"
```

Prompts for the macOS login password. This is the command the wrapper's
`install --yes` runs over an interactive SSH session. The older binary name
`dayone2` still works for existing installs but is deprecated — prefer `dayone`.

## Command syntax

```
dayone [options] command
```

The only supported command is `new`, which creates a journal entry.

### `new`

Creates an entry from the trailing text argument, or from **standard input** when
no text is given (the default).

```bash
dayone new "entry text here"
echo "entry text here" | dayone new
```

### Options

| Option | Purpose |
|--------|---------|
| `--journal <name>` | Target journal (must already exist; defaults to the primary journal). |
| `--tags <t1> <t2> …` | One or more tags to attach. |
| `--attachments <f1> … --` | Up to 10 files (photos, videos, audio, PDFs). Use `--` before `new` when attachments are the last option. |
| `--date '2015-06-01 15:53:10'` | Entry date; time optional. |
| `--isoDate 2015-06-01T15:53:10Z` | Entry date in ISO 8601. |
| `--all-day` | Mark the entry as spanning the whole day. |
| `--starred` | Star the entry. |
| `--coordinate <lat> <lon>` | Attach a location. |
| `--time-zone <IANA zone>` | Set the timezone (IANA names, e.g. `America/Denver`). |
| `--no-stdin` | Ignore standard input. |
| `-h`, `--help` | Show help. |
| `-v`, `--version` | Show version. |

### Attachment ordering note

Because `--attachments` is variadic, put `--` between the file list and the
`new` command when attachments come last:

```bash
dayone --attachments ~/Pictures/a.jpg ~/Pictures/b.jpg -- new "Trip photos"
```

Attachment paths resolve on the **macOS host** filesystem, not the container.

## Wrapper: `dayone-host.sh`

The wrapper runs `dayone` locally on the host, or over SSH from a devcontainer.

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `check` | Report whether the app + CLI are usable. |
| `install [--yes]` | Run the app-bundle installer on the host (opt-in; needs `--yes`). |
| `new [flags]` | Create an entry; text is read from stdin and base64-transported. |
| `raw [args]` | Pass arguments straight through to `dayone` (advanced, e.g. attachments). |
| `version` | Print the host `dayone` version. |

### Wrapper exit codes

| Code | Meaning |
|------|---------|
| 0 | Success / CLI installed and working. |
| 2 | `install` invoked without `--yes` (consent backstop). |
| 3 | No host user configured (`DAYONE_HOST_USER` unset and `$USER` empty). |
| 4 | macOS host unreachable over SSH. |
| 10 | Day One app present but CLI not installed — installable via `install --yes`. |
| 11 | Day One app not found on the host. |
| 64 | Unknown subcommand. |

### Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DAYONE_HOST_USER` | `$HOST_USER`, else `$USER` | macOS host username for SSH. Defaults to the container-wide `HOST_USER` (set by this devcontainer for host access), falling back to the local `$USER`. |
| `DAYONE_HOST` | `host.docker.internal` | SSH host. |
| `DAYONE_SSH_OPTS` | `-o BatchMode=yes` (non-tty) | Extra ssh options. |
| `DAYONE_FORCE_MODE` | auto | Force `local` or `remote` instead of auto-detecting. |

### How it decides local vs. remote

- Runs **locally** if the OS is macOS (`uname -s` = `Darwin`) or `dayone` is
  already on `PATH`.
- Otherwise runs **remotely**, SSHing to `${DAYONE_HOST_USER}@${DAYONE_HOST}`.

## Troubleshooting

- **`check` returns 4 (host unreachable):** Enable Remote Login on the Mac
  (System Settings → General → Sharing → Remote Login). Confirm
  `ssh <user>@host.docker.internal` works with key auth. If the host username
  differs from the container `$USER`, set `DAYONE_HOST_USER`.
- **`install` hangs or fails over SSH:** `sudo` needs an interactive terminal.
  The wrapper allocates a TTY (`ssh -t`) for `install` so the password prompt
  reaches you. If automation still can't supply the password, run the installer
  command directly on the host, then re-run `dayone-host.sh check`.
- **"Journal not found":** Create the journal in the Day One app first; the CLI
  cannot create journals.
- **Entry didn't appear:** Ensure the Day One app has been opened at least once
  and is signed in; the CLI writes into the same local database the app manages.
- **`dayone: command not found` after install:** Open a fresh shell so the new
  `/usr/local/bin/dayone` is on `PATH`, or re-run `check`.
