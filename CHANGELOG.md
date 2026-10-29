# Changelog

格式遵循 [Keep a Changelog 2.0.0](https://keepachangelog.com/en/2.0.0/)，版本号遵循 [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)。

## [1.6.0] - 2026-10-29

### Added（新增）

- 新增 WorkBuddy 实际积分口径：
  - 列表新增 `-ActualCredits` 开关：带上后积分列切换为实际积分（列头 `ActualCredits`），子智能体行显示实际数值，不再为 `-`；
  - `-s` / `-c` 详情视图并列显示 `Credits`（显示积分）与 `ActualCredits`（实际积分）两行；
  - `-AsJson` 输出新增 `ActualCredits` 字段，原 `Credits` 字段含义不变。
- 新增 `-FullSessionId` 开关：列表显示完整会话编号，codex / claude / workbuddy 三数据源生效；不带时保持缩略显示。

### Changed（变更）

- 详情视图（`-s` / `-c`）的 token 子字段由纯缩进改为树形连接线前缀（`├─` / `└─`），末项为 `└─`。
- WorkBuddy 积分说明统一为「显示积分 / 实际积分」两个概念：显示积分为 WorkBuddy 界面口径，会话派发的子智能体消耗合并计入该会话名下；实际积分为该会话自身每次请求扣费逐条相加的总数，子智能体单独成行、各算各的。

### Fixed（修复）

- 修复详情视图 `CacheWriteTokens` 行数值右移两列、个位与其他行不对齐的问题。

## [1.5.1] - 2026-10-26

### Added（新增）

- 新增 WorkBuddy 会话的 Turns（轮次）与 Requests（请求数）统计：
  - `-s` / `-c` 详情视图与 `-AsJson` 输出恒含；
  - 列表新增 `-Turns` / `-Requests` 可选列开关（默认隐藏）。

### Changed（变更）

- WorkBuddy 自定义模型在列表与详情视图显示为 `BYOK:<模型名>`（原 `custom-local:<模型名>`）；`-AsJson` 输出保持原值。
- 详情视图（`-s` / `-c`）的 token 子字段缩进为 Tokens 的从属项，全部数字右对齐，Credits 与 Tokens 字段组相邻（三数据源同步）。
- 列表数字列宽按当前页内容自适应（WorkBuddy 的 Tokens / Credits / Turns / Requests 列与 codex / claude 的 Tokens 列）。

## [1.5.0] - 2026-10-19

### Added（新增）

- 新增 WorkBuddy 子智能体的状态派生，列表与详情可见其运行状态。

### Fixed（修复）

- 修复 WorkBuddy 子智能体的 Model 列恒为空的问题。
- 修复会话标题含 ① 等符号时列表各列错位的问题。

## [1.4.3] - 2026-10-10

### Changed（变更）

- 列表态的 SessionId 由完整编号改为缩略显示：前 2 个字符 + `**` + 后 6 个字符，占 10 个字符位。`-c` / `-s` 详情与 `-AsJson` 输出仍为完整编号。
- 列表态的 WorkspacePath 列加宽。
- `-s` 支持按 SessionId 子串模糊匹配：先按完整编号精确匹配，未命中则按子串匹配，命中多条时逐条输出详情。

### Fixed（修复）

- 修复工作区路径中混用 `\` 与 `/` 的问题，统一为 Windows 路径分隔符。

## [1.4.2] - 2026-10-08

### Fixed（修复）

- 修复 Codex 会话的中文标题与项目路径可能被改错的问题。
- 修复 WorkBuddy 列表在 Token 数据退化时不提示的问题。
- 修复 Claude 恢复命令在会话编号含空格或特殊符号时不可执行的问题。

### Changed（变更）

- Claude 恢复命令中的会话编号改为单引号包裹。

## [1.4.1] - 2026-09-21

### Changed（变更）

- WorkBuddy 会话标题改为多级回退取值：人工重命名 → AI 更新标题 → 会话库标题 → 首条用户消息。

### Fixed（修复）

- 修复子智能体会话标题显示为一串标识符的问题，改为显示会话标题。

## [1.4.0] - 2026-09-18

### Added（新增）

- WorkBuddy 列表新增 `Status` 列，展示会话状态（`completed` / `working` / `archived` / `error` 等，原样输出）；该列默认显示。
- 新增三个列表可选列开关：`-HideStatus` 关闭 `Status` 列，`-Tokens` / `-Credits` 分别打开对应的可选列。

### Changed（变更）

- WorkBuddy 列表默认隐藏 `Tokens` 与 `Credits` 两列。需要这两列时用 `-Tokens` / `-Credits` 打开。
- 三个可选列开关仅作用于 workbuddy 列表渲染；`-s` / `-c` 详情视图与 `-AsJson` 输出恒为全字段，不受影响；对 codex / claude 源无效（静默忽略）。

## [1.3.0] - 2026-09-17

### Added（新增）

- 新增 WorkBuddy 积分消耗（`Credits`）查询与统计展示：会话列表、`-c` / `-s` 详情与 `-AsJson` 输出均展示会话积分消耗合计，无积分数据以 `-`（JSON 为 `null`）表示。

## [1.2.1] - 2026-09-10

### Fixed（修复）

- 澄清 `-d` / `-WithinDays` 非法值的报错文案（2026-09-10）：原「…，收到「abc」。」的双层中文引号易被误读为标记或指令，改为「…；本次输入：abc。」；并为关键字补充中文释义（`week` 本周周一起、`month` 本月 1 号起），同时把「天数 < 1」一支的措辞与「非法值」一支统一。仅影响提示文案，参数行为与退出码（exit 1）不变。

## [1.2.0] - 2026-09-09

### Added（新增）

- 新增通用选项 `-d` / `-WithinDays <N|Nd|关键字>`（2026-09-09）：按会话「最后活动时间（LastActivity）」筛选，如「今日活动的会话」。三数据源（codex / claude / workbuddy）均可用，作用于列表视图（默认列表、`-c`、`-AsJson`），对 `-s` 单会话详情视图不适用。
  - 口径：`today` = 今日（自然日 00:00 起）；`yesterday` = 昨日；`week` = 本周（自然周，本周一 00:00 起，周一为一周之首）；`month` = 本月（自然月，1 号 00:00 起）；数字 `7`/`7d`/`N`/`Nd` = 滚动近 N 天。时间窗口均按本地时间计算。
  - 与既有筛选正交：与路径/`-g`、`-q`/`-t` 检索、`-Type`、`-SortBy`、`-Limit` 组合使用；筛选在排序与条数截断之前执行。
  - 容错：非数字/关键字、小于 1 的天数统一中文报错并 exit 1；空结果走既有人话兜底并回显时间筛选条件。
  - 边界：LastActivity 为「时间未知」（MinValue 哨兵）的会话一律不命中。
- 新增本地测试覆盖（`tests/` 不随开源发布）：按运行当天动态生成自然日/周/月边界锚点会话，断言 today / yesterday / week / month / 滚动 N 的包含与排除，及非法输入的 exit 1 与中文报错。

## [1.1.2] - 2026-09-07

### Fixed（修复）

- 采纳外部贡献者 [@liyangbing](https://github.com/liyangbing) 的路径匹配修复（社区 [PR #1](https://github.com/iuuunlyk/AgentSessionQuery/pull/1)，pull request，拉取请求）：`-IncludeSubdirectories` 过滤原硬编码 Windows 反斜杠 `\`，改为以 `[System.IO.Path]::DirectorySeparatorChar` 对当前工作区与会话工作区路径做平台无关归一化（兼容 `AltDirectorySeparatorChar`），使 `-r` 目录分隔符处理更健壮。**注意**：asq 仍仅面向 Windows 设计（见 README「开发者说明」），本 PR 属防御性加固，不表示已支持 macOS / Linux。

### Changed（变更）

- 版本号改为单一真源：新增 `$ScriptVersion` 变量（当前 `v1.1.2`），`asq -h` 帮助文本的 `-v` 说明与 `-v` / `-Version` 输出均引用该变量；发版时仅改一处即可，消除此前三处硬编码版本字面易遗漏的问题。`asq -v` 现输出 `v1.1.2`。
- 明确运行平台定向（Windows）：README 新增「操作系统」环境要求、「开发者说明」节与「已知限制」条目，明确 asq 仅面向 Windows 设计，macOS / Linux 不在支持范围；[PR #1](https://github.com/iuuunlyk/AgentSessionQuery/pull/1)（pull request，拉取请求）的路径分隔符归一化属防御性加固，不表示已支持上述平台。

## [1.1.0] - 2026-09-03

### Changed（变更）

- 重构 `asq -h` 帮助文本与来源/条数错误提示（2026-09-03）：帮助顶部新增用法概要行 `asq <codex|claude|workbuddy> [选项]` 并点明「来源是唯一必填项」，正文按「查询来源 → 通用选项 → 来源专属选项」分节、示例精简；缺失/非法来源与条数非数字的错误提示改为带正确写法与 `asq -h` 指引的文案（替换原「详见 帮助查看参数使用介绍」的生硬措辞）。`-h` / `-?` / `--help` 行为不变，仍显示同一套总帮助。
- Claude 查询链路输出字段 `ModelId` 统一为 `Model`（2026-09-03）：列表列名、`-c` / `-s` 详情标签与 `-AsJson` 键名均改为 `Model`，与 codex / workbuddy 两数据源列名一致（值为每会话最后实际跑的真实模型，含义不变）。
- `-SortBy` 取值收敛为 `LastActivity` / `WorkspacePath` 两值（2026-09-03）：移除历史别名 `time` / `path` / `cwd`（曾用旧值的调用需改用规范名），`-o` 短参数与默认值（LastActivity）不变。

### Removed（移除）

- 退役三个旧子命令 `codex-sessions` / `claude-sessions` / `workbuddy-sessions` 及其 wrapper 脚本 `codex-sessions.ps1` / `claude-sessions.ps1` / `workbuddy-sessions.ps1`（2026-09-03）：`session-profile-aliases.ps1` 仅注册统一命令 `asq`，查询一律使用 `asq codex|claude|workbuddy [选项]`（来源位置参数）或 `asq -Source <来源> [选项]`。

### Fixed（修复）

- 修正 `asq.ps1` 头部版本注释：由 `v0.2.4` 改为 `v1.0.0`，与 `--version` / `-v` 实际输出一致（v1.0.0 起 `--version` 即输出 `v1.0.0`）。属注释修正，不影响运行行为与版本输出。

## [1.0.0] - 2026-09-01

### Added（新增）

- 首次对公开发布 AgentsSessionQuery（asq）统一会话查询工具套件：整合 `codex-sessions` / `claude-sessions` / `workbuddy-sessions` 三条命令，并提供统一入口 `asq`（Agents Sessions Query）。
- 三条命令均支持：列表与模糊检索（`-q` / `-t`）、模型展示、可恢复命令（`-c` / `-s`）、脚本化 JSON 输出（`-AsJson`）、Token 统计（6 字段，与 token-monitor / tokscale 口径对齐）与三态数据源检测（未安装 / 已装未用 / 已用）。
- 统一命令 `asq`：以 `-Source codex|claude|workbuddy` 或来源位置参数（如 `asq codex -g`）查询；`-v` / `-Version` 显示版本号。
- `session-profile-aliases.ps1`：将三条命令注册为 PowerShell Profile 同名函数，新开终端即可直接使用。

[1.3.0]: https://github.com/iuuunlyk/AgentSessionQuery/releases/tag/v1.3.0
[1.2.1]: https://github.com/iuuunlyk/AgentSessionQuery/releases/tag/v1.2.1
[1.2.0]: https://github.com/iuuunlyk/AgentSessionQuery/releases/tag/v1.2.0
[1.1.2]: https://github.com/iuuunlyk/AgentSessionQuery/releases/tag/v1.1.2
[1.1.0]: https://github.com/iuuunlyk/AgentSessionQuery/releases/tag/v1.1.0
[1.0.0]: https://github.com/iuuunlyk/AgentSessionQuery/releases/tag/v1.0.0
