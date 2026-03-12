# Session Recorder — Changelog

## [1.3.0] - 2026-03-11

### Added
- **Solution Replay Protocol**: 4-stage guided replay (dependency installation → **adaptation analysis** → step-by-step replay → deviation handling)
- **Structured execution_plan**: `execution_plan` upgraded from string to structured array with `step`, `phase`, `detail`, `skills_used`, `key_decisions`, `outcome`, `errors`
- **Skill install metadata**: `skills` array items now include `install_command` and `source` fields for automated dependency installation
- **Backward compatibility**: `execution_plan` supports `oneOf[string, array]` — old string format still valid

### Changed
- `execution_step` log entries now include `skills_used` and `key_decisions` fields
- Report JSON Structure table updated to reflect new field types
- Execution Step Tracking compilation format changed from string concatenation to structured array
- Report examples expanded to 3 examples (added solution replay scenario)

### Optimized (writing-skills audit)
- **Frontmatter description**: Changed from "what it does" to "Use when..." trigger format (CSO optimization)
- **Token efficiency**: Extracted Solution Replay Protocol (~100 lines) to `references/solution-replay-protocol.md`, SKILL.md reduced ~35%
- **Structure reorg**: State Machine + HARD-RULE moved before features (foundation-first reading flow)
- **Redundancy removal**: Auto-Execute persistence code block consolidated, repeated explanations eliminated
- **Section tightening**: All sections made more concise while preserving complete business logic

## [1.2.0] - 2026-03-11

### Optimized
- **Token efficiency**: Extracted all examples into `references/` files, SKILL.md reduced ~45%
- **Per-Turn Protocol**: Merged Step 1+4 into single batched write, reduced tool calls per turn from 3+ to 1-2
- **Summary updates**: Changed from every-turn overwrite to key-event-only updates
- **Priority order**: Added explicit rule priority declaration for conflict resolution

### Added
- **Resilience rules**: curl timeouts, dependency install failure handling, consecutive failure skip
- **Version management**: Added `version` field to frontmatter
- `references/log-examples.jsonl` — on-demand log format guidance
- `references/report-examples.json` — on-demand report compilation guidance
- `references/communication-examples.md` — on-demand beginner communication guidance
- `references/CHANGELOG.md` — this file

## [1.1.0] - 2026-03-11

### Added
- Solution Community Search (vector search before starting work)
- Auto-Execute Mode (skip confirmations, persisted across sessions)
- Adaptive Communication (per-domain proficiency detection, 5 rules for beginners)
- find-skills dependency check and auto-installation
- Log Richness Rules (self-contained, context-rich logging)
- Execution Step Tracking (feeds into execution_plan)

### Changed
- API server address updated to `https://cookbook-dev.ominieye.dev`
- IMMEDIATE-ACTION block added for reliable activation

## [1.0.0] - 2026-03-10

### Initial Release
- Session recording state machine (IDLE → ACTIVE → COMPLETING → DONE)
- JSONL append-only logging
- Rolling summary (session-summary.md)
- Final JSON report compilation and server upload
- Error tracking (5 source types)
- Platform adaptation (Hook detection)
