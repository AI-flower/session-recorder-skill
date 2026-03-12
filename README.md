# Session Recorder

A Claude Code skill that silently records the full AI session lifecycle and compiles structured JSON reports. It runs as a **background protocol** alongside all your other work — never blocks, never interferes.

## Features

- **Session Lifecycle Recording** — Automatically tracks state transitions (IDLE → ACTIVE → DONE), tool calls, decisions, errors, and execution steps
- **Solution Community** — Searches a shared solution database before starting work; reuse proven approaches from past sessions
- **Adaptive Communication** — Detects user's domain expertise level per request and adjusts communication style accordingly
- **Structured Reports** — Compiles session data into JSON reports and uploads to the community server
- **Hook-Based Capture** — SessionStart and PostToolUse hooks auto-record tool calls without AI involvement
- **Auto-Execute Mode** — Skip interactive confirmations; AI makes all decisions automatically

## Installation

```bash
bash install.sh
```

This will:
1. Copy plugin files to `~/.claude/plugins/cache/local/session-recorder/`
2. Register SessionStart and PostToolUse hooks in `~/.claude/settings.json`
3. Set correct file permissions

Verify installation:
```bash
bash install.sh --check
```

### Requirements

- Claude Code
- Bash 4+
- Python 3

## Uninstallation

```bash
bash uninstall.sh
```

Or skip confirmations:
```bash
bash uninstall.sh --force
```

## How It Works

### State Machine

```
IDLE ──→ ACTIVE ──→ DONE
  ↑                   │
  └───────────────────┘
       (new task)
```

| State | Meaning |
|-------|---------|
| IDLE | Session started, waiting for user's first substantive request |
| ACTIVE | Working and recording every turn |
| DONE | Task complete, compiling and submitting final report |

### Session Files

Each project generates local session data under `.session-recorder/`:

```
.session-recorder/
├── session-log.jsonl        # Append-only event log
├── session-summary.md       # Rolling progress summary
└── reports/
    └── {timestamp}-{summary}.json
```

> Add `.session-recorder/` to your `.gitignore` — these are local runtime files.

### Report Structure

| Field | Type | Description |
|-------|------|-------------|
| `task_description` | string | User's goal in one sentence |
| `skills` | array | Skills invoked during the session |
| `execution_plan` | string | Numbered steps with phase, detail, outcome |
| `is_successful` | boolean | Whether the task was completed successfully |
| `error_message` | string | All errors encountered, empty if none |

## Project Structure

```
session-recorder/
├── SKILL.md                 # Core skill definition (loaded by Claude Code)
├── install.sh               # One-click installer
├── uninstall.sh             # Clean uninstaller
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
├── hooks/
│   ├── hooks.json           # Hook configuration
│   ├── session-start        # SessionStart hook (bash)
│   ├── post-tool-use        # PostToolUse hook (python3)
│   └── run-hook.cmd         # Windows hook runner
├── references/
│   ├── report-schema.json   # Report JSON schema
│   ├── report-examples.json # Example reports
│   ├── log-examples.jsonl   # Good/bad log entry examples
│   ├── communication-examples.md
│   └── solution-replay-protocol.md
└── docs/
    └── report-content-analysis.md
```

## License

MIT
