# Mercury Plugin

The Mercury plugin lets you manage your Mercury bank accounts directly from Claude Code. Check balances, review transactions, send payments, and handle invoices -- all through natural conversation without leaving your terminal.

## What can I ask?

You can interact with your Mercury accounts using everyday language:

- "Check my balance"
- "How much is in my account?"
- "Show me my accounts"
- "Show recent transactions"
- "What came in this week?"
- "Who did I pay last month?"
- "Send money to someone"
- "Create an invoice"
- "What invoices are outstanding?"
- "Show unpaid invoices"
- "What payments are pending?"

## Installation

```bash
/plugin install mercury@crewchief
```

After installation, verify the plugin is loaded:

```bash
/plugin list
```

You should see `mercury` in the list of installed plugins.

## Features

- **Account Overview** - View balances and account details across all your Mercury accounts
- **Transaction History** - Browse and search through recent transactions with filters
- **Payments** - Send money to recipients and review pending payments
- **Invoicing** - Create, send, and track invoices and their payment status

## Configuration

### Setting Up Your Token

The plugin requires a `MERCURY_TOKEN` environment variable to authenticate with your Mercury account. To generate a token:

1. Log in to your Mercury dashboard
2. Navigate to Settings > Tokens
3. Create a new token with the permissions you need (read-only for viewing, read-write for payments and invoicing)
4. Copy the token value

Set the token in your environment. Add it to your shell profile or devcontainer configuration:

```bash
export MERCURY_TOKEN="your-token-here"
```

For devcontainer users, add it to your `devcontainer.json`:

```json
{
  "remoteEnv": {
    "MERCURY_TOKEN": "your-token-here"
  }
}
```

**Important:** Keep your token secure. Do not commit it to version control. Use environment variables or a secrets manager.

## Skills Reference

| Skill       | Description                                                           | Documentation                           |
| ----------- | --------------------------------------------------------------------- | --------------------------------------- |
| mercury-api | Banking operations for accounts, transactions, payments, and invoices | [SKILL.md](skills/mercury-api/SKILL.md) |

## Directory Structure

```text
plugins/mercury/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── mercury-api/
│       ├── SKILL.md
│       └── references/
└── README.md
```

## Troubleshooting

### Authentication Failure

**Problem**: Requests fail with an authentication error.

**Solution**:

1. Verify your token is set:
   ```bash
   echo $MERCURY_TOKEN
   ```
2. Confirm the token has not expired in your Mercury dashboard
3. Regenerate the token if needed and update your environment variable

### Missing Token

**Problem**: "MERCURY_TOKEN not set" error when attempting banking operations.

**Solution**:
Set the `MERCURY_TOKEN` environment variable as described in the Configuration section above. If you are in a devcontainer, rebuild the container after updating `devcontainer.json`.
