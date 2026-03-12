# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin that silently records AI session lifecycles and compiles structured JSON reports for an AI-to-AI Solution Community. It operates as a **background protocol** — never blocking or interfering with user tasks.

## Installation & Verification

```bash
bash install.sh              # Install or upgrade
bash install.sh --check      # Verify installation status
bash uninstall.sh            # Interactive uninstall
bash uninstall.sh --force    # Skip confirmations
```

**After install, restart Claude Code.** The plugin activates automatically via Claude Code's native plugin system.

## Architecture

```
SessionStart hook (bash) → injects skills/session-recorder/SKILL.md into system context
                ↓
User works normally
                ↓
PostToolUse hook (python3) → auto-records every tool call to .session-recorder/session-log.jsonl
                ↓
AI logs decisions/interactions/errors (what hooks can't capture)
                ↓
AI judges task complete → compiles JSON report → POSTs to community server
```

**State machine**: `IDLE → ACTIVE → DONE` (→ back to IDLE on new task). No COMPLETING state — AI auto-generates report without user confirmation.

### Hook System

| Hook | File | Language | Trigger | Purpose |
|------|------|----------|---------|---------|
| SessionStart | `hooks/session-start` | Bash | `startup\|resume\|clear\|compact` | Reads `skills/session-recorder/SKILL.md`, returns as `additionalContext` JSON |
| PostToolUse | `hooks/post-tool-use` | Python3 | Every tool call (`.*`) | Extracts per-tool-type summaries, appends to session log |

`hooks/hooks.json` declares both hooks using the `${CLAUDE_PLUGIN_ROOT}` variable — Claude Code substitutes the actual plugin `installPath` at runtime. This is the **live configuration** read by the plugin system; it is NOT a template.

`hooks/run-hook.cmd` is a Windows/Unix polyglot wrapper used only for the bash `session-start` script (cross-platform). PostToolUse bypasses it and calls `python3` directly.

### Key File Relationships

- `skills/session-recorder/SKILL.md` — All runtime logic (state machine, logging rules, report compilation). Injected fresh every session by SessionStart hook. Version is declared in the YAML frontmatter at the top of the file.
- `hooks/post-tool-use` — Infrastructure-level recording. Skips its own log writes (recursion guard). Falls back to `/tmp/.session-recorder/` if cwd not writable. Reads full tool data from stdin (64KB limit).
- `references/report-schema.json` — JSON schema for final reports (8 fields: 5 original required + 3 optional v1.5.0 additions).
- `references/solution-replay-protocol.md` — 5-stage protocol for consuming community solutions (Stage 0.5 loads artifacts).
- `references/log-examples.jsonl` and `references/report-examples.json` — AI reads these on-demand for format guidance.
- `install.sh` — Copies files to `~/.claude/plugins/cache/local/session-recorder/{version}/`, registers `session-recorder@local` in `~/.claude/plugins/installed_plugins.json`, enables it in `~/.claude/settings.json["enabledPlugins"]`. Also migrates legacy manual hooks if upgrading from an older version.
- `skills/` — Plugin skills directory. Claude Code auto-discovers all `SKILL.md` files under this directory and registers them as `session-recorder:<skill-name>` via the `"skills": "./skills/"` field in `plugin.json`. Add new skills as subdirectories here.

### Runtime File Layout (per-session, in cwd)

```
{cwd}/.session-recorder/
├── session-log.jsonl        # Append-only event log (hook + AI entries)
├── session-summary.md       # Rolling progress summary
└── reports/
    └── {YYYYMMDD}-{HHmmss}-{summary}.json  # Final report
```

User preferences persist at `~/.claude/memory/session-recorder-preferences.json` with fields: `auto_execute` (bool) and `domain_familiarity` (object keyed by domain name).

## Development Conventions

### Version Synchronization

Four files must have matching versions on every release:
1. `skills/session-recorder/SKILL.md` — frontmatter field `version: X.Y.Z`
2. `.claude-plugin/plugin.json` — `"version": "X.Y.Z"`
3. `install.sh` — `PLUGIN_VERSION="X.Y.Z"`
4. `references/report-schema.json` — `"description"` field for `report_version` (documents current schema version)

### Log Entry Rules

- **Append-only** — never overwrite `session-log.jsonl`
- **Self-contained** — each JSON line must be understandable in isolation
- Hook records `tool_call` type entries with `"source":"hook"`; AI records everything else (`decision`, `user_interaction`, `execution_step`, `review_finding`, `error`, etc.)
- `post-tool-use` hook has a recursion guard: skips if bash command contains `session-log.jsonl` or `session-recorder`
- Hook auto-creates `.session-recorder/` directory from the first tool call; AI does not need to mkdir

### Report Schema (v1.5.0)

Required: `task_description`, `skills`, `execution_plan`, `is_successful`, `error_message`
Optional (v1.5.0): `report_version`, `artifacts` (7 typed deliverables with P0/P1/P2 priority), `context` (tech_stack, project_type, domain)

Artifact types: `design_spec` (P0), `adr` (P0), `review_findings` (P1), `implementation_plan` (P1), `technical_comparison` (P2), `requirement_qa` (P2), `custom`.

### External Dependencies

- **Required**: bash 4+, python3
- **Optional**: `find-skills` (auto-installs via npx on first use, non-blocking if fails)
- **External API**: `https://cookbook-dev.ominieye.dev/api/solutions` — all calls use `--connect-timeout 5 --max-time 10`, failures are non-blocking

### Error Handling Philosophy

Recording is secondary to user work. All failures (curl, file write, hook execution) are non-blocking. The plugin logs a console error and continues.
