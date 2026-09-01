# Changelog

本文件记录 **AgentsSessionQuery** 套件（子命令 `codex-sessions` / `claude-sessions` / `workbuddy-sessions`，以及统一命令 `asq`）的版本演进。

格式遵循 [Keep a Changelog 2.0.0](https://keepachangelog.com/en/2.0.0/)，版本号遵循 [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)。

套件采用统一发布版本（v1.x.y）；各工具（Codex / Claude / WorkBuddy）的内部组件版本演进与历史明细见 `CHANGELOG.private.md`（本地，不随开源发布）。

## [Unreleased]

## [v1.0.0] - 2026-09-01

### Added（新增）

- 首次对公开发布 AgentsSessionQuery（asq）统一会话查询工具套件：整合 `codex-sessions` / `claude-sessions` / `workbuddy-sessions` 三条命令，并提供统一入口 `asq`（Agents Sessions Query）。
- 三条命令均支持：列表与模糊检索（`-q` / `-t`）、模型展示、可恢复命令（`-c` / `-s`）、脚本化 JSON 输出（`-AsJson`）、Token 统计（6 字段，与 token-monitor / tokscale 口径对齐）与三态数据源检测（未安装 / 已装未用 / 已用）。
- 统一命令 `asq`：以 `-Source codex|claude|workbuddy` 或来源位置参数（如 `asq codex -g`）查询；`-v` / `-Version` 显示版本号。
- `session-profile-aliases.ps1`：将三条命令注册为 PowerShell Profile 同名函数，新开终端即可直接使用。

[v1.0.0]: https://github.com/your-project/AgentsSessionQuery/releases/tag/v1.0.0
