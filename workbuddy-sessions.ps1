<#
WorkBuddy 会话列表工具（规划 1 单命令重构 · 转发 wrapper）
版本: v1.0.6
更新日期: 2026-08-14
兼容性说明：本文件已重构为 asq.ps1 -Source workbuddy 的转发 wrapper。
  所有采集（含内嵌 Python 只读桥接）/ token 解析 / 过滤 / 排序 / 输出逻辑已迁移至统一命令 asq.ps1；
  此处保留原命令名与帮助文本，使既有脚本、别名与调用方零改动过渡。
  参数算法口径见 asq.ps1（移植自本文件 v1.0.6）。CHANGELOG.md 记录完整历史。
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$DbPath = (Join-Path $HOME '.workbuddy\workbuddy.db'),
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
    [Alias('s')]
    [string]$SessionId,
    [Alias('o')]
    [ValidateSet('LastActivity', 'WorkspacePath', 'cwd', 'time', 'path')]
    [string]$SortBy = 'LastActivity',
    [ValidateSet('任务', '空间')]
    [string]$Type,
    [Alias('h', '?')]
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs,
    [switch]$AsJson
)

function Show-WorkBuddySessionsHelp {
    @'
workbuddy-sessions - 本机 WorkBuddy 历史会话列表工具

用法:
  workbuddy-sessions                                  # 默认：按当前路径过滤，显示最近 20 条会话清单
  workbuddy-sessions 50                               # 位置参数即 Limit：显示最近 50 条（等价于 -n 50）
  workbuddy-sessions -n 50                            # -n 为 Limit 别名：限制输出条数为 50
  workbuddy-sessions -g                               # -g / -Global：全局模式，不按当前路径过滤，列出全部会话
  workbuddy-sessions -r                               # -r / -IncludeSubdirectories：当前路径及其子目录下的会话
  workbuddy-sessions -c                               # -c / -ShowCommands：详细视图，输出完整字段（Mode/SourceMode/PermissionMode/Status 等）
  workbuddy-sessions -q 6c6cb9d0                      # -q / -SessionIdLike：在 SessionId / Title / WorkspacePath 三者上统一模糊匹配
  workbuddy-sessions -q scripts                        # -q 同上：此处按工作区路径片段匹配
  workbuddy-sessions -t "某个标题"                    # -t / -TitleLike：仅按 Title 模糊匹配（不匹配 id 或路径）
  workbuddy-sessions -Type 任务                       # -Type：按派生类型筛选（任务 = 沙盒/后台自动化；空间 = 真实项目）
  workbuddy-sessions -s 6c6cb9d0-9fac-4a8c-a9d9-96c703adbaf3   # -s / -SessionId：单会话完整详情，忽略路径过滤
  workbuddy-sessions -o WorkspacePath                # -o / -SortBy：按工作区路径升序（time→LastActivity、path/cwd→WorkspacePath）
  workbuddy-sessions -AsJson                          # -AsJson：输出 JSON（多条为数组、单条为对象）
  workbuddy-sessions -DbPath "$HOME\workbuddy-backup.db"   # -DbPath：指定数据库文件路径（默认 ~/.workbuddy/workbuddy.db），可读取备份或迁移后的库；token 真源优先取 <库目录>/projects，缺失时回退 ~/.workbuddy/projects

参数:
  -c
    显示详细视图（含 Mode / SourceMode / PermissionMode / Status 等完整字段）
  -s <sessionId>, -SessionId <sessionId>
    查看指定会话的完整详情（忽略路径过滤）
  -q <检索词>
    按 SessionId / Title / WorkspacePath 统一模糊筛选
  -t <标题检索词>, -TitleLike <标题检索词>
    只按 Title 模糊筛选，不匹配 SessionId 或 WorkspacePath
  -Type <任务|空间>
    按派生类型筛选（任务 = 沙盒/后台自动化会话；空间 = 真实项目会话）
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
    也可直接写数字，例如: workbuddy-sessions 50
  -DbPath <路径>
    指定 workbuddy.db 路径（默认 ~/.workbuddy/workbuddy.db）
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

if ($Help -or ($RemainingArgs -contains '--help') -or ($RemainingArgs -contains '-?')) {
    Show-WorkBuddySessionsHelp
    exit 0
}

& "$PSScriptRoot/asq.ps1" -Source workbuddy @PSBoundParameters
