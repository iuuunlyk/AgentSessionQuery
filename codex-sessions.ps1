<#
Codex 活动工具套件（规划 1 单命令重构 · 转发 wrapper）
版本: v1.2.7
更新日期: 2026-08-14
兼容性说明：本文件已重构为 asq.ps1 -Source codex 的转发 wrapper。
  所有采集 / token 解析 / 过滤 / 排序 / 输出逻辑已迁移至统一命令 asq.ps1；
  此处保留原命令名与帮助文本，使既有脚本、别名与调用方零改动过渡。
  参数算法口径见 asq.ps1（移植自本文件 v1.2.7）。CHANGELOG.md 记录完整历史。
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$RootPath = (Join-Path $HOME '.codex'),
    [Parameter(Position = 0)]
    [Alias('n')]
    [object]$Limit = 20,
    [Alias('c')]
    [switch]$ShowCommands,
    [Alias('q')]
    [string]$SessionIdLike,
    [Alias('t')]
    [string]$TitleLike,
    [Alias('g')]
    [switch]$Global,
    [Alias('r')]
    [switch]$IncludeSubdirectories,
    [string]$WorkspacePath = (Get-Location).Path,
    [Alias('o')]
    [ValidateSet('LastActivity', 'WorkspacePath', 'time', 'path')]
    [string]$SortBy = 'LastActivity',
    [Alias('h', '?')]
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs,
    [switch]$AsJson
)

function Show-CodexSessionsHelp {
    @'
codex-sessions - 本机 Codex / OMX session 列表工具

用法:
  codex-sessions                                  # 默认：按当前路径过滤，显示最近 20 条会话清单
  codex-sessions 50                               # 位置参数即 Limit：显示最近 50 条（等价于 -n 50）
  codex-sessions -n 50                            # -n 为 Limit 别名：限制输出条数为 50
  codex-sessions -g                               # -g / -Global：全局模式，不按当前路径过滤，列出全部会话
  codex-sessions -r                               # -r / -IncludeSubdirectories：当前路径及其子目录下的会话
  codex-sessions -c                               # -c / -ShowCommands：详细视图，输出完整字段（路径、resume 命令、分支、模式等）
  codex-sessions -q 019d8778                      # -q / -SessionIdLike：在 SessionId / Title / WorkspacePath 三者上统一模糊匹配
  codex-sessions -q scripts                        # -q 同上：此处按工作区路径片段匹配
  codex-sessions -t "飞行数字化"                  # -t / -TitleLike：仅按 Title 模糊匹配（不匹配 id 或路径）
  codex-sessions -WorkspacePath "$HOME\scripts"   # -WorkspacePath：指定筛选的工作区路径（默认当前 PowerShell 路径）
  codex-sessions -o WorkspacePath                # -o / -SortBy：按工作区路径升序（time→LastActivity、path→WorkspacePath）
  codex-sessions -AsJson                          # -AsJson：输出 JSON（多条为数组、单条为对象）

参数:
  -c
    显示详细命令视图（含会话路径、resume 命令、分支、模式等完整字段）
  -q <检索词>
    按 SessionId / Title / WorkspacePath 统一模糊筛选
  -t <标题检索词>, -TitleLike <标题检索词>
    只按 Title 模糊筛选，不匹配 SessionId 或 WorkspacePath
  -g, -Global
    显示全局 session，不按当前路径筛选
  -r, -IncludeSubdirectories
    在当前路径筛选中包含子目录 session
  -WorkspacePath <路径>
    指定用于筛选 session 工作区的路径
    默认: 当前 PowerShell 路径
  -o <LastActivity|WorkspacePath|time|path>
    排序方式
    默认: LastActivity
    正式参数名: -SortBy
  -Limit <N>, -n <N>
    限制输出条数
    默认: 20
    也可直接写数字，例如: codex-sessions 50
  -AsJson
    输出 JSON
  -h, -?, --help
    显示帮助
'@
}

$helpTokens = @('--help', '-help', 'help')
if (($Limit -is [string]) -and ($helpTokens -contains $Limit)) {
    $Help = $true
    $Limit = 20
}

# -h / 位置 'help'：显示本命令原帮助（不转发到统一帮助），保持既有调用方行为不变
if ($Help -or ($RemainingArgs -contains '--help') -or ($RemainingArgs -contains '-?')) {
    Show-CodexSessionsHelp
    exit 0
}

# 转发到统一命令（规划 1）。-Source 由本 wrapper 固定；其余参数原样透传。
& "$PSScriptRoot/asq.ps1" -Source codex @PSBoundParameters
