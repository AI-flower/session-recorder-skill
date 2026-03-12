# Changelog

## [1.5.0] - 2026-03-12

### Added
- report 新增 `artifacts` 字段：纳入 spec、plan、ADR、评审发现等 7 类产出物，信息损失率从 >99% 降至接近 0
- report 新增 `context` 字段：tech_stack、project_type、domain，便于消费端快速判断适配难度
- report 新增 `report_version` 字段：schema 版本标识，向后兼容
- 新增 `review_finding` log 类型：捕获 spec/code review 中的评审发现
- `decision` log 新增可选 `alternatives` 字段：记录被否决的替代方案及原因
- Solution Replay Protocol 新增 Stage 0.5 (Artifact Loading)：消费端 AI 加载 spec/ADR/评审发现作为执行上下文
- Stage 1.5/2 支持基于 artifact 的适配分析和执行

### Changed
- Final Report Compilation 新增 Step 3.5 (artifact 编译) 和 Step 3.6 (context 构建)
- report-schema.json 移除 additionalProperties: false，支持新字段

## [1.4.0] - 2026-03-12

### Changed
- 状态机从 4 状态简化为 3 状态：取消 COMPLETING，AI 判断完成后直接生成报告
- 报告生成不再需要用户显式确认，完全无感
- HARD-RULE 从 8 条精简为 7 条，新增"尽可能生成报告"原则
- 用户取消/放弃任务时也自动生成报告（is_successful: false）

### Removed
- COMPLETING 状态及所有相关的确认交互逻辑
- COMPLETING → ACTIVE 回滚机制（不再需要）

## [1.3.1] - 2026-03-11

### Fixed
- PostToolUse hook 工具名全部为 "unknown" 的 bug（改读 stdin JSON 而非环境变量）
- report-schema.json `execution_plan` 从 `oneOf[string, array]` 统一为 `string`（与服务端 API 一致）
- HARD-RULE #1 明确 hook 和 AI 的分工，AI 不再冗余记录 tool_call

### Changed
- PostToolUse hook 从 bash 重写为 python3，从 stdin 读取完整 JSON 数据
- 新增 per-tool-type 摘要提取（target + result_summary），覆盖 Bash/Write/Edit/Read/Glob/Grep/Skill/Agent/WebSearch/WebFetch 等工具
- 基础设施级记录：AI 自主执行时工具调用也会被 hook 自动记录，不再依赖 AI 自律
- Hook 自动创建 `.session-recorder/` 目录，从第一次工具调用就开始记录
- install.sh 中 PostToolUse command 从 `bash` 改为 `python3`
- report-examples.json 全部转为 string 格式的 execution_plan

## [1.3.0] - 2026-03-09

### Added
- Initial release with session lifecycle recording
- Solution Community search and replay
- Adaptive communication by domain expertise
- SessionStart and PostToolUse hooks
