# Solution Replay Protocol

Referenced from SKILL.md when user selects a community solution. Read this file on-demand.

## Overview

When user selects a community solution, execute 5-stage guided replay:

```
Stage 0.5  Artifact Loading — load specs, ADRs, review findings as context
Stage 1    Dependency Installation — ensure all skills available
Stage 1.5  Adaptation Analysis — proactive gap analysis and plan adaptation
Stage 2    Guided Replay — execute adapted plan step by step
Stage 3    Deviation Handling — handle runtime divergence
```

## Stage 0.5: Artifact Loading

**Skip if** `solution.artifacts` is absent or empty (backward compat with pre-1.5.0 reports).

Load artifacts by priority, building context for subsequent stages:

| Artifact Type | How Consuming AI Uses It |
|---------------|------------------------|
| `design_spec` (P0) | **Primary adaptation reference.** Load as the spec to adapt — skip brainstorming, directly modify sections for current task. |
| `adr` (P0) | **Pre-validated decisions.** Present as "community-proven choices" during replay. Accept or explicitly override with reasoning. |
| `review_findings` (P1) | **Known pitfalls checklist.** Cross-check during implementation to proactively avoid same bugs. |
| `implementation_plan` (P1) | **Code reference.** Use structure/patterns as template, adapt for tech stack differences. |
| `technical_comparison` (P2) | **Decision context.** Understand why certain tech was chosen — helps when adapting to different stack. |
| `requirement_qa` (P2) | **Scope hints.** Know what questions to ask current user to clarify scope quickly. |

Log `execution_step` with `phase="solution replay: artifact loading"`.

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

### Artifact-Aware Adaptation (when artifacts present)

When `design_spec` artifact exists:
- Adaptation analysis operates at **spec section level**, not just execution step level.
- Compare spec sections (requirements, architecture, data model, API, UI) against current task.
- Classify each section: `reusable` / `adaptable` / `not_applicable`.
- Output: section-level adaptation plan alongside step-level plan.

When `adr` artifact exists:
- Present each ADR as: "社区方案选择了 X 而非 Y，原因是 Z。当前任务是否沿用？"
- User/AI confirms or overrides each decision.

When `review_findings` artifact exists:
- Integrate into adapted plan: "第 N 步实现时，注意社区方案发现的已知问题：{finding}，已知解决方案：{resolution}"

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

### Replay with Artifacts

- **With spec**: Write adapted spec first (fast, since reference exists), then implement. Replaces brainstorming phase.
- **With ADRs**: Each architectural decision point during replay is pre-answered. Log decisions noting "adopted from community ADR" or "overridden: {reason}".
- **With review findings**: After each implementation step, cross-check against known issues list. Proactively apply fixes.

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
