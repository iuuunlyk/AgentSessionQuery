# Changelog

本文件记录 **AgentsSessionQuery** 套件（统一命令 `asq`，按 `-Source` 覆盖 codex / claude / workbuddy 三数据源）的版本演进。v1.0.0 曾以三个子命令（`codex-sessions` / `claude-sessions` / `workbuddy-sessions`）为兼容入口，2026-09-03 起退役删除、仅保留统一命令 `asq`（见 [v1.1.0]）。

格式遵循 [Keep a Changelog 2.0.0](https://keepachangelog.com/en/2.0.0/)，版本号遵循 [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)。

套件采用统一发布版本（v1.x.y）；各工具（Codex / Claude / WorkBuddy）的内部组件版本演进与历史明细见 `CHANGELOG.private.md`（本地，不随开源发布）。

## [1.1.0] - 2026-09-03

### Changed（变更）

- 重构 `asq -h` 帮助文本与来源/条数错误提示（2026-09-03）：帮助顶部新增用法概要行 `asq <codex|claude|workbuddy> [选项]` 并点明「来源是唯一必填项」，正文按「查询来源 → 通用选项 → 来源专属选项」分节、示例精简；缺失/非法来源与条数非数字的错误提示改为带正确写法与 `asq -h` 指引的文案（替换原「详见 帮助查看参数使用介绍」的生硬措辞）。`-h` / `-?` / `--help` 行为不变，仍显示同一套总帮助。
- Claude 查询链路输出字段 `ModelId` 统一为 `Model`（2026-09-03）：列表列名、`-c` / `-s` 详情标签与 `-AsJson` 键名均改为 `Model`，与 codex / workbuddy 两数据源列名一致（值为每会话最后实际跑的真实模型，含义不变）。
- `-SortBy` 取值收敛为 `LastActivity` / `WorkspacePath` 两值（2026-09-03）：移除历史别名 `time` / `path` / `cwd`（曾用旧值的调用需改用规范名），`-o` 短参数与默认值（LastActivity）不变。

### Removed（移除）

- 退役三个旧子命令 `codex-sessions` / `claude-sessions` / `workbuddy-sessions` 及其 wrapper 脚本 `codex-sessions.ps1` / `claude-sessions.ps1` / `workbuddy-sessions.ps1`（2026-09-03）：`session-profile-aliases.ps1` 仅注册统一命令 `asq`，查询一律使用 `asq codex|claude|workbuddy [选项]`（来源位置参数）或 `asq -Source <来源> [选项]`。

### Fixed（修复）

- 修正 `asq.ps1` 头部版本注释：由 `v0.2.4` 改为 `v1.0.0`，与 `--version` / `-v` 实际输出一致（v1.0.0 起 `--version` 即输出 `v1.0.0`）。属注释修正，不影响运行行为与版本输出。

## [v1.0.0] - 2026-09-01

### Added（新增）

- 首次对公开发布 AgentsSessionQuery（asq）统一会话查询工具套件：整合 `codex-sessions` / `claude-sessions` / `workbuddy-sessions` 三条命令，并提供统一入口 `asq`（Agents Sessions Query）。
- 三条命令均支持：列表与模糊检索（`-q` / `-t`）、模型展示、可恢复命令（`-c` / `-s`）、脚本化 JSON 输出（`-AsJson`）、Token 统计（6 字段，与 token-monitor / tokscale 口径对齐）与三态数据源检测（未安装 / 已装未用 / 已用）。
- 统一命令 `asq`：以 `-Source codex|claude|workbuddy` 或来源位置参数（如 `asq codex -g`）查询；`-v` / `-Version` 显示版本号。
- `session-profile-aliases.ps1`：将三条命令注册为 PowerShell Profile 同名函数，新开终端即可直接使用。

[v1.1.0]: https://github.com/iuuunlyk/AgentSessionQuery/releases/tag/v1.1.0
[v1.0.0]: https://github.com/iuuunlyk/AgentSessionQuery/releases/tag/v1.0.0
