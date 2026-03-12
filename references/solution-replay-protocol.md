# Solution Replay Protocol

Referenced from SKILL.md when user selects a community solution. Read this file on-demand.

## Overview

When user selects a community solution, execute 4-stage guided replay:

```
Stage 1    Dependency Installation — ensure all skills available
Stage 1.5  Adaptation Analysis — proactive gap analysis and plan adaptation
Stage 2    Guided Replay — execute adapted plan step by step
Stage 3    Deviation Handling — handle runtime divergence
```

## Stage 1: Dependency Installation

Before replaying, ensure all required skills are available:

```
For each skill in solution.skills:
  1. install_command is null → built-in, verify: test -f <expected_path>
  2. install_command exists → run it (e.g. npx skills add ... -g -y)
  3. Install fails → warn user, log error, continue (non-blocking)
  4. Log execution_step: phase="solution replay: dependency installation"
```

Present installation summary:
```
依赖检查完成：
  [installed] superpowers:brainstorming (内置)
  [installed] cloudflare-deploy (已安装: npx skills add ...)
  [skipped]   custom-lint (安装失败，跳过)
```

## Stage 1.5: Solution Adaptation Analysis

**Proactively** analyze the gap between community solution and current task before replaying:

1. **Compare scope:** Solution's `task_description` vs current user goal — identify overlap and divergence.
2. **Per-step assessment:** For each step in `execution_plan`, classify:

| Classification | Meaning | Action |
|----------------|---------|--------|
| `reusable` | Directly applicable | Replay as-is |
| `adaptable` | Same intent, different tech/details | Replay with modifications |
| `not_applicable` | Irrelevant to current task | Skip |
| `missing` | Current task needs steps not in original | Create new steps |

3. **Present adaptation plan to user:**
```
方案适配分析：
  原方案：{solution.task_description}
  当前任务：{current_goal}

  Step 1 [{phase}] → 可复用（{reason}）
  Step 2 [{phase}] → 需调整（{what_changes}）
  Step 3 [{phase}] → 不适用（{why}）
  + 新增步骤：{description}（原方案未覆盖）

  适配建议：{summary}
```

4. **User confirms or adjusts** → Produce **adapted execution plan** (reordered/merged/new steps).
5. **Log** `execution_step` with `phase="solution replay: adaptation analysis"`.

**Auto-execute ON:** Skip confirmation, proceed with AI's adapted plan.

**ALL steps `not_applicable`:** Warn user, suggest declining and starting from scratch.

## Stage 2: Guided Replay

Walk through the **adapted execution plan** (from Stage 1.5) step by step:

```
For each step in adapted_plan:
  1. Present: "Step {N}/{total}: [{phase}] {detail}" + classification
  2. Adaptable steps: show what changed vs original and why
  3. Execute in current project context
  4. skills_used → invoke those skills
  5. Log execution_step: phase="solution replay: {original_phase}"
  6. Outcome differs → note in log, continue
```

- **Array format execution_plan**: Full metadata for analysis and replay.
- **String format execution_plan**: Parse numbered lines, Stage 1.5 with limited metadata (AI infers from text).

## Stage 3: Deviation Handling

When current context diverges from the adapted plan:

1. **Minor deviation** (file names, config differences) → Adapt silently, log.
2. **Major deviation** (tech stack, missing dependency, user rejects step) → Pause:
   ```
   原方案在此步使用了 {original_approach}，但当前项目情况不同：{difference}。
   建议：{adapted_approach}。继续吗？
   ```
3. **Remaining steps applicable** → Continue from deviation point.
4. **Remaining steps not applicable** → Exit replay, switch to normal workflow. Log `decision`.

After completion (or exit), log `execution_step` with `phase="solution replay: summary"` noting replayed/adapted/skipped counts.
