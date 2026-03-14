# Session Recorder

[![Live Demo](https://img.shields.io/badge/demo-session--recorder.pages.dev-22C55E?style=flat-square)](https://session-recorder.pages.dev)
[![Version](https://img.shields.io/badge/version-1.7.0-38BDF8?style=flat-square)]()
[![License](https://img.shields.io/badge/license-MIT-gray?style=flat-square)]()

A Claude Code plugin that silently records the full AI session lifecycle and compiles structured JSON reports. It runs as a **background protocol** alongside all your other work — never blocks, never interferes.

> **[View Landing Page →](https://session-recorder.pages.dev)**

## Features

- **Silent Lifecycle Recording** — 5 hooks auto-capture tool calls, user messages, AI responses. Zero interference with your workflow.
- **Solution Community** — Searches a shared AI-to-AI solution database before starting work; reuse proven approaches from past sessions.
- **Structured JSON Reports** — 8-field reports with artifacts, context, and execution plans. Schema v1.5.0 with 7 artifact types.
- **3-State Machine** — IDLE → ACTIVE → DONE with automatic state transitions and context recovery after compaction.
- **Adaptive Communication** — Detects user's domain expertise level per request and adjusts communication style accordingly.
- **Auto-Execute Mode** — Skip interactive confirmations; AI makes all decisions automatically.

## Quick Start

```bash
# Install
git clone <repo-url> session-recorder
cd session-recorder && bash install.sh

# Verify
bash install.sh --check

# Restart Claude Code — the plugin activates automatically
```

### Requirements

- Claude Code
- Bash 4+
- Python 3
- macOS / Linux

## How It Works

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

### Hook Architecture

| Hook | Language | Trigger | Purpose |
|------|----------|---------|---------|
| SessionStart | bash | `startup\|resume\|compact\|clear` | Injects SKILL.md + session event into context |
| UserPromptSubmit | python3 | Every user message | Records full message content |
| PostToolUse | python3 | Every tool call | Per-tool-type summaries with recursion guard |
| Stop | python3 | Every AI reply ends | Records AI response + triggers report compilation |
| SessionEnd | python3 | Session closes | Fallback: auto-compiles basic report if needed |

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

### Report Schema (v1.5.0)

| Field | Type | Description |
|-------|------|-------------|
| `task_description` | string | User's goal in one sentence |
| `skills` | array | Skills invoked during the session |
| `execution_plan` | string | Numbered steps with phase, detail, outcome |
| `is_successful` | boolean | Whether the task was completed successfully |
| `error_message` | string | All errors encountered, empty if none |
| `report_version` | string | Schema version ("1.5.0") |
| `artifacts` | array | Deliverables: specs, plans, ADRs, review findings |
| `context` | object | Metadata: tech_stack, project_type, domain |

## Project Structure

```
session-recorder/
├── install.sh                  # One-click installer
├── uninstall.sh                # Clean uninstaller
├── landing-page/
│   └── index.html              # Project landing page (deployed to CF Pages)
├── .claude-plugin/
│   └── plugin.json             # Plugin metadata
├── hooks/
│   ├── hooks.json              # Hook configuration
│   ├── session-start           # SessionStart hook (bash)
│   ├── user-prompt-submit      # UserPromptSubmit hook (python3)
│   ├── post-tool-use           # PostToolUse hook (python3)
│   ├── stop                    # Stop hook (python3)
│   ├── session-end             # SessionEnd hook (python3)
│   ├── session_recorder_utils.py  # Shared utilities
│   └── run-hook.cmd            # Windows/Unix polyglot runner
├── skills/
│   └── session-recorder/
│       └── SKILL.md            # Core skill definition
└── references/
    ├── report-schema.json
    ├── report-examples.json
    ├── log-examples.jsonl
    ├── communication-examples.md
    └── solution-replay-protocol.md
```

## Uninstall

```bash
bash uninstall.sh           # Interactive
bash uninstall.sh --force   # Skip confirmations
```

## License

MIT
