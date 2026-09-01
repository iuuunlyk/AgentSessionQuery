<#
Codex、Claude 与 WorkBuddy 会话工具套件
版本: v1.3.4
更新日期: 2026-08-14
说明: 注册 codex-sessions、claude-sessions、workbuddy-sessions 与统一命令 asq 四个日常命令函数，供本机 PowerShell Profile 点加载。
本版更新（v1.3.4，v0.2 统一命令重构补全 · 注册统一命令 asq）: 新增 function asq 透传至 asq.ps1（其自身已处理 -Source / 位置来源 / 五种帮助令牌），
          使 asq / asq codex -g 等可直接调用；三个包装函数维持直连统一命令 asq.ps1 -Source codex|claude|workbuddy（1 个进程跃点），
          -h / --help 仍委托对应 wrapper 脚本展示「各源专属帮助文本」。
          所有采集 / token 解析 / 过滤 / 排序 / 输出逻辑均位于 asq.ps1（唯一真源）。
详细记录: CHANGELOG.md
历史:
  v1.3.4 — 注册统一命令 asq：新增 function asq 透传至 asq.ps1（其已处理 -Source / 位置来源 / 五种帮助令牌），补全 v0.2 重构遗漏（此前 asq 未被注册为 Profile 命令，README/CHANGELOG 的 asq 示例无法直呼）。
  v1.3.3 — v0.2 统一命令重构 · 别名直连统一命令：三个包装函数改为直连 asq.ps1 -Source codex|claude|workbuddy（1 个进程跃点，规避此前经 wrapper 脚本的二次跃点）；-h / --help 仍委托对应 wrapper 脚本展示各源专属帮助文本。
  v1.3.2 — 移除 StrictMode 全局泄漏：删除文件顶层 Set-StrictMode -Version Latest，避免经 Profile 点加载后泄漏到用户交互式会话。
  v1.3.1 — 修复 workbuddy-sessions 包装转发：改用哈希表展开（按参数名绑定）转发参数，仅在显式传入 -Type 时加入 Type 键。
#>

$script:SessionScriptsRoot = $PSScriptRoot
$script:CodexSessionsScript = Join-Path $script:SessionScriptsRoot 'codex-sessions.ps1'
$script:ClaudeSessionsScript = Join-Path $script:SessionScriptsRoot 'claude-sessions.ps1'
$script:WorkBuddySessionsScript = Join-Path $script:SessionScriptsRoot 'workbuddy-sessions.ps1'
$script:AgentsSessionQueryScript = Join-Path $script:SessionScriptsRoot 'asq.ps1'

function codex-sessions {
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

    $helpTokens = @('--help', '-help', 'help')
    if (($Limit -is [string]) -and ($helpTokens -contains $Limit)) {
        $Help = $true
        $Limit = 20
    }

    if ($RootPath -eq '--help') {
        $Help = $true
        $RootPath = Join-Path $HOME '.codex'
    }

    if ($Help -or ($RemainingArgs -contains '--help') -or ($RemainingArgs -contains '-?')) {
        & $script:CodexSessionsScript -h
        return
    }

    & $script:AgentsSessionQueryScript -Source codex @PSBoundParameters
}


function claude-sessions {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [string]$RootPath = (Join-Path $HOME '.claude'),
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
        [Alias('h', '?')]
        [switch]$Help,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$RemainingArgs,
        [switch]$AsJson
    )

    $helpTokens = @('--help', '-help', 'help')
    if (($Limit -is [string]) -and ($helpTokens -contains $Limit)) {
        $Help = $true
        $Limit = 20
    }

    if ($RootPath -eq '--help') {
        $Help = $true
        $RootPath = Join-Path $HOME '.claude'
    }

    if ($Help -or ($RemainingArgs -contains '--help') -or ($RemainingArgs -contains '-?')) {
        & $script:ClaudeSessionsScript -h
        return
    }

    & $script:AgentsSessionQueryScript -Source claude @PSBoundParameters
}


function workbuddy-sessions {
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

    $helpTokens = @('--help', '-help', 'help')
    if (($Limit -is [string]) -and ($helpTokens -contains $Limit)) {
        $Help = $true
        $Limit = 20
    }

    if ($DbPath -eq '--help') {
        $Help = $true
        $DbPath = Join-Path $HOME '.workbuddy\workbuddy.db'
    }

    # 改用哈希表展开（按参数名绑定）。注意：数组展开 @array 是「按位置」绑定，
    # 若把 @('-Type', $Type) 展开进 & 调用，-Type 会被当成位置值而非参数名，导致脚本 $Type 接收不到。
    # -Type 仅在用户显式传入时加入哈希表：否则 $Type 为空，脚本 [string] 强制成 "" 会触发
    # [ValidateSet('任务','空间')] 校验失败。
    $wbParams = @{
        DbPath                 = $DbPath
        Limit                 = $Limit
        ShowCommands          = $ShowCommands
        SessionIdLike         = $SessionIdLike
        TitleLike             = $TitleLike
        Global                = $Global
        IncludeSubdirectories = $IncludeSubdirectories
        WorkspacePath         = $WorkspacePath
        SessionId             = $SessionId
        SortBy                = $SortBy
        Help                  = $Help
        AsJson                = $AsJson
    }
    if (-not [string]::IsNullOrWhiteSpace($Type)) {
        $wbParams['Type'] = $Type
    }

    if ($Help -or ($RemainingArgs -contains '--help') -or ($RemainingArgs -contains '-?')) {
        & $script:WorkBuddySessionsScript -h
        return
    }

    & $script:AgentsSessionQueryScript -Source workbuddy @wbParams @RemainingArgs
}

function asq {
    & $script:AgentsSessionQueryScript @args
}
