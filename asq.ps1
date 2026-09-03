<#
AgentsSessionQuery 统一命令（规划 1 单命令重构）
版本: v1.1.0
更新日期: 2026-08-31
本命令是 OpenAI Codex / Claude Code / WorkBuddy 三客户端会话记录的统一查询入口：
  - 通过 -Source codex|claude|workbuddy 选择查询对象；来源也可写为第一个位置参数（asq codex -g）；
  - 三套采集算法（含 token 解析口径）逐字移植自原三脚本，字段 schema 与输出格式零回归；
  - 统一参数容错（Limit 非数字 → 人话报错，列出本次开关含 -Source）、统一三态数据源检测、
    统一过滤/排序/Limit、统一 Format-SessionCell 截断对齐；按 Source 分发表 / -AsJson / -c 详情 / -s 详情。
  - 原三脚本（codex-sessions.ps1 / claude-sessions.ps1 / workbuddy-sessions.ps1，转发 wrapper）已退役删除，
    套件收敛为单一命令 asq（session-profile-aliases.ps1 仅注册 asq 函数）。

原三脚本版本与算法说明（保持口径一致）：
  codex-sessions  v1.2.7  — stateful-delta token 解析（last_token_usage 增量主源）
  claude-sessions v1.2.9  — (message.id, requestId) 去重 + 分量 MAX 合并
  workbuddy-sessions v1.0.6 — input_exclusive 缓存减法 + 多键去重
详细记录: CHANGELOG.md
#>

[CmdletBinding(PositionalBinding = $true)]
param(
    # 查询来源：既可用 -Source codex 命名传入，也可作为第一个位置参数直接写 codex（即 asq codex -g）
    [Parameter(Position = 0)]
    [string]$Source,

    # Codex / Claude 数据根目录；WorkBuddy 用 -DbPath
    [string]$RootPath,
    # WorkBuddy 数据库文件路径
    [string]$DbPath,

    [Parameter(Position = 1)]
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
    [ValidateSet('LastActivity', 'WorkspacePath')]
    [string]$SortBy = 'LastActivity',

    [ValidateSet('任务', '空间')]
    [string]$Type,

    [Alias('h')]
    [switch]$Help,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs,

    [switch]$AsJson,

    [Alias('v')]
    [switch]$Version
)

Set-StrictMode -Version Latest

if ($PSVersionTable.PSEdition -eq 'Desktop') {
    Write-Warning '建议使用 PowerShell 7 (pwsh) 运行本工具；当前为 Windows PowerShell 5.1，中文可能乱码。'
}

# ============================================================================
# 统一单元格截断/对齐（合并自三脚本同构实现）
#   - 显示宽度：ASCII(≤0x7F) 算 1，其余（含中文/CJK）算 2，按 Unicode 文本元素切分；
#   - 常规列超宽时末端截断（Mode='end'，末尾加 '...'）；
#   - WorkspacePath 路径列中间截断（Mode='middle'）；
#   - 单元格内换行统一压成空格，避免撑破列宽计算。
# ============================================================================
function Format-SessionCell {
    param(
        [AllowNull()]
        [string]$Text,
        [int]$Width,
        [ValidateSet('end', 'middle')]
        [string]$Mode = 'end',
        [ValidateSet('left', 'right')]
        [string]$Align = 'left'
    )

    if ($null -eq $Text) {
        $Text = ''
    }
    $Text = $Text -replace "`r?`n", ' '

    $textElements = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    $elements = New-Object System.Collections.Generic.List[string]
    while ($textElements.MoveNext()) {
        $elements.Add($textElements.GetTextElement())
    }

    function Get-SessionCellDisplayWidth {
        param([string]$Value)
        $width = 0
        $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Value)
        while ($enumerator.MoveNext()) {
            $element = $enumerator.GetTextElement()
            $codePoint = [int][char]$element[0]
            if ($codePoint -le 0x7F) {
                $width += 1
            } else {
                $width += 2
            }
        }
        return $width
    }

    $displayWidth = Get-SessionCellDisplayWidth -Value $Text
    if ($displayWidth -le $Width) {
        if ($Align -eq 'right') {
            return (' ' * ($Width - $displayWidth)) + $Text
        }
        return $Text + (' ' * ($Width - $displayWidth))
    }

    $ellipsis = '...'
    $ellipsisWidth = 3
    if ($Width -le $ellipsisWidth) {
        return $ellipsis.Substring(0, $Width)
    }

    if ($Mode -eq 'middle') {
        $targetWidth = $Width - $ellipsisWidth
        $leftTarget = [Math]::Floor($targetWidth / 2)
        $rightTarget = $targetWidth - $leftTarget

        $leftText = ''
        $leftWidth = 0
        foreach ($element in $elements) {
            $elementWidth = Get-SessionCellDisplayWidth -Value $element
            if (($leftWidth + $elementWidth) -gt $leftTarget) {
                break
            }
            $leftText += $element
            $leftWidth += $elementWidth
        }

        $rightText = ''
        $rightWidth = 0
        for ($i = $elements.Count - 1; $i -ge 0; $i--) {
            $element = $elements[$i]
            $elementWidth = Get-SessionCellDisplayWidth -Value $element
            if (($rightWidth + $elementWidth) -gt $rightTarget) {
                break
            }
            $rightText = $element + $rightText
            $rightWidth += $elementWidth
        }

        $result = $leftText + $ellipsis + $rightText
        $resultWidth = Get-SessionCellDisplayWidth -Value $result
        if ($resultWidth -lt $Width) {
            $result += (' ' * ($Width - $resultWidth))
        }
        return $result
    }

    $resultText = ''
    $resultWidth = 0
    foreach ($element in $elements) {
        $elementWidth = Get-SessionCellDisplayWidth -Value $element
        if (($resultWidth + $elementWidth + $ellipsisWidth) -gt $Width) {
            break
        }
        $resultText += $element
        $resultWidth += $elementWidth
    }

    $result = $resultText + $ellipsis
    $finalWidth = Get-SessionCellDisplayWidth -Value $result
    if ($finalWidth -lt $Width) {
        if ($Align -eq 'right') {
            $result = (' ' * ($Width - $finalWidth)) + $result
        } else {
            $result += (' ' * ($Width - $finalWidth))
        }
    }
    return $result
}

# ============================================================================
# Codex 采集（移植自 codex-sessions.ps1 v1.2.7）
# ============================================================================
function Get-CodexSessionIdFromPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $match = [regex]::Match([System.IO.Path]::GetFileName($Path), '(?<id>[0-9a-fA-F-]{36})(?=\.jsonl$)')
    if ($match.Success) {
        return $match.Groups['id'].Value.ToLowerInvariant()
    }

    return $null
}

function Convert-CodexEscapedString {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    return [regex]::Unescape($Value)
}

function Repair-CodexMojibake {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    $suspiciousPattern = '�|妞ゅ|娲伴|椤|鍗|鍐呴儴|浣庤|璧勬枡|鏍囧噯|鍘嗗彶|绾跨▼|閸|鏉|惃|鍤|顖|妫€|淇?|浠樺?|姒傝堪|鍏抽敭|闃屾柟'
    if ($Value -notmatch $suspiciousPattern) {
        return $Value
    }

    try {
        $bytes = [System.Text.Encoding]::GetEncoding(936).GetBytes($Value)
        $candidate = [System.Text.Encoding]::UTF8.GetString($bytes)
        if (
            (-not [string]::IsNullOrWhiteSpace($candidate)) -and
            ($candidate -notmatch '�') -and
            ($candidate -match '[一-龥]')
        ) {
            return $candidate
        }
    } catch {
    }

    return $Value
}

function Get-CodexSessionMeta {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TranscriptPath
    )

    foreach ($line in Get-Content -Encoding UTF8 $TranscriptPath -TotalCount 20) {
        if ($line -notmatch '"type":"session_meta"') {
            continue
        }

        try {
            $item = $line | ConvertFrom-Json
        } catch {
            continue
        }

        return $item.payload
    }

    return $null
}

function Get-CodexLane {
    param(
        $SessionMeta
    )

    if (-not $SessionMeta) {
        return 'Codex'
    }

    $baseInstructions = $null
    $baseInstructionsProp = $SessionMeta.PSObject.Properties['base_instructions']
    if ($baseInstructionsProp -and $baseInstructionsProp.Value) {
        $textProp = $baseInstructionsProp.Value.PSObject.Properties['text']
        if ($textProp -and $textProp.Value) {
            $baseInstructions = $textProp.Value
        }
    }

    if (
        ($baseInstructions -match 'oh-my-codex') -or
        ($baseInstructions -match 'omx:generated:agents-md') -or
        ($baseInstructions -match 'OMX')
    ) {
        return 'OMX'
    }

    return 'Codex'
}

function Get-CodexSessionIndexMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $indexPath = Join-Path $RootPath 'session_index.jsonl'
    $indexMap = @{}

    if (-not (Test-Path $indexPath)) {
        return $indexMap
    }

    $pattern = '"id":"(?<id>[0-9a-fA-F-]{36})".*?"thread_name":"(?<thread>(?:\\.|[^"])*)".*?"updated_at":"(?<updated>[^"]+)"'
    foreach ($line in Get-Content -Encoding UTF8 $indexPath) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $match = [regex]::Match($line, $pattern)
        if (-not $match.Success) {
            continue
        }

        $sessionId = $match.Groups['id'].Value.ToLowerInvariant()
        $threadName = Repair-CodexMojibake (Convert-CodexEscapedString $match.Groups['thread'].Value)
        $updatedAtText = $match.Groups['updated'].Value

        $updatedAt = $null
        try {
            $updatedAt = [DateTimeOffset]::Parse($updatedAtText)
        } catch {
            $updatedAt = [DateTimeOffset]::MinValue
        }

        if (
            (-not $indexMap.ContainsKey($sessionId)) -or
            ($updatedAt -ge $indexMap[$sessionId].UpdatedAt)
        ) {
            $indexMap[$sessionId] = [pscustomobject]@{
                ThreadName = $threadName
                UpdatedAt  = $updatedAt
            }
        }
    }

    return $indexMap
}

function Get-CodexSessionModel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TranscriptPath
    )

    $turnModel = $null
    $fallbackModel = $null

    try {
        foreach ($line in Get-Content -Encoding UTF8 $TranscriptPath) {
            if ($line -notmatch '"model"') {
                continue
            }

            $o = $null
            try {
                $o = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
            } catch {
                continue
            }
            if ($null -eq $o) {
                continue
            }

            $m = $null
            if ($o.PSObject.Properties['model'] -and $o.model -is [string]) {
                $m = $o.model
            } elseif (
                $o.PSObject.Properties['payload'] -and
                $o.payload -and
                $o.payload.PSObject.Properties['model'] -and
                $o.payload.model -is [string]
            ) {
                $m = $o.payload.model
            }
            if ([string]::IsNullOrWhiteSpace($m)) {
                continue
            }

            if ($m -eq '<synthetic>') { continue }
            if ($m -match 'image') { continue }
            if ($m -match 'openrouter/free') { continue }

            if ($o.PSObject.Properties['type'] -and $o.type -eq 'turn_context') {
                $turnModel = $m
            } else {
                $fallbackModel = $m
            }
        }
    } catch {
        return $null
    }

    if ($turnModel) {
        return $turnModel
    }
    return $fallbackModel
}

function Get-CodexTokenUsage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TranscriptPath
    )

    function Get-CodexTokenNumber {
        param($Obj, [string[]]$Keys)
        if ($null -eq $Obj) { return $null }
        foreach ($k in $Keys) {
            if ($Obj.PSObject.Properties[$k] -and $null -ne $Obj.$k) {
                $v = $Obj.$k
                if ($v -is [int] -or $v -is [long] -or $v -is [double] -or ($v -is [string] -and $v -match '^\d+$')) {
                    return [long]$v
                }
            }
        }
        return $null
    }

    function Get-CodexTotals {
        param($Usage)
        if ($null -eq $Usage) { return $null }
        $inp = Get-CodexTokenNumber -Obj $Usage -Keys @('input_tokens','inputTokens','prompt_tokens')
        $out = Get-CodexTokenNumber -Obj $Usage -Keys @('output_tokens','outputTokens','completion_tokens')
        $cit = Get-CodexTokenNumber -Obj $Usage -Keys @('cached_input_tokens')
        $cri = Get-CodexTokenNumber -Obj $Usage -Keys @('cache_read_input_tokens')
        $cachedRaw = [Math]::Max($(if ($null -eq $cit) { 0 } else { $cit }), $(if ($null -eq $cri) { 0 } else { $cri }))
        $reason = Get-CodexTokenNumber -Obj $Usage -Keys @('reasoning_output_tokens','reasoningTokens')
        $i = $(if ($null -eq $inp)    { 0 } else { [Math]::Max(0, $inp) })
        $o = $(if ($null -eq $out)    { 0 } else { [Math]::Max(0, $out) })
        $c = [Math]::Max(0, $cachedRaw)
        $r = $(if ($null -eq $reason) { 0 } else { [Math]::Max(0, $reason) })
        return @{
            input     = $i
            output    = $o
            cached    = $c
            reasoning = $r
        }
    }

    function Get-CodexTotalsDelta {
        param($Cur, $Prev)
        if ($Cur.input -lt $Prev.input -or $Cur.output -lt $Prev.output -or $Cur.cached -lt $Prev.cached -or $Cur.reasoning -lt $Prev.reasoning) {
            return $null
        }
        return @{
            input     = $Cur.input - $Prev.input
            output    = $Cur.output - $Prev.output
            cached    = $Cur.cached - $Prev.cached
            reasoning = $Cur.reasoning - $Prev.reasoning
        }
    }

    function Test-CodexTotalsEqual {
        param($A, $B)
        return ($A.input -eq $B.input -and $A.output -eq $B.output -and $A.cached -eq $B.cached -and $A.reasoning -eq $B.reasoning)
    }

    function Test-CodexStaleRegression {
        param($Cur, $Prev, $Last)
        $pt = $Prev.input + $Prev.output + $Prev.cached + $Prev.reasoning
        $ct = $Cur.input + $Cur.output + $Cur.cached + $Cur.reasoning
        $lt = $Last.input + $Last.output + $Last.cached + $Last.reasoning
        if ($pt -le 0 -or $ct -le 0 -or $lt -le 0) { return $false }
        return ($ct * 100 -ge $pt * 98) -or ($ct + $lt * 2 -ge $pt)
    }

    function ConvertTo-CodexBreakdown {
        param($T)
        $clamped = [Math]::Min($T.cached, $T.input)
        if ($clamped -lt 0) { $clamped = 0 }
        return @{
            input       = [Math]::Max(0, $T.input - $clamped)
            output      = [Math]::Max(0, $T.output)
            cache_read  = $clamped
            cache_write = 0
            reasoning   = [Math]::Max(0, $T.reasoning)
        }
    }

    function Add-CodexTotals {
        param($A, $B)
        return @{
            input     = $A.input + $B.input
            output    = $A.output + $B.output
            cached    = $A.cached + $B.cached
            reasoning = $A.reasoning + $B.reasoning
        }
    }

    $aggInput = 0; $aggOutput = 0; $aggCacheRead = 0; $aggCacheWrite = 0; $aggReasoning = 0
    $prev = $null
    try {
        foreach ($line in Get-Content -Encoding UTF8 $TranscriptPath) {
            if ($line -notmatch 'token_count') { continue }
            $o = $null
            try { $o = $line | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { continue }
            if ($null -eq $o) { continue }

            $payload = $null
            if ($o.PSObject.Properties['payload'] -and $o.payload) { $payload = $o.payload }
            if ($null -eq $payload -or -not $payload.PSObject.Properties['type'] -or $payload.type -ne 'token_count') { continue }

            $info = $null
            if ($payload.PSObject.Properties['info'] -and $payload.info) { $info = $payload.info }
            if ($null -eq $info) { continue }

            $totalUsage = $null
            if ($info.PSObject.Properties['total_token_usage'] -and $info.total_token_usage) {
                $totalUsage = Get-CodexTotals -Usage $info.total_token_usage
            }
            $lastUsage = $null
            if ($info.PSObject.Properties['last_token_usage'] -and $info.last_token_usage) {
                $lastUsage = Get-CodexTotals -Usage $info.last_token_usage
            }

            if ($null -eq $totalUsage -and $null -eq $lastUsage) { continue }

            $tokens = $null
            $nextTotals = $null
            if ($null -ne $totalUsage -and $null -ne $lastUsage -and $null -ne $prev) {
                if (Test-CodexTotalsEqual $totalUsage $prev) { continue }
                $d = Get-CodexTotalsDelta $totalUsage $prev
                if ($null -eq $d -and (Test-CodexStaleRegression $totalUsage $prev $lastUsage)) { continue }
                $tokens = ConvertTo-CodexBreakdown $lastUsage
                $nextTotals = $totalUsage
            }
            elseif ($null -ne $totalUsage -and $null -ne $lastUsage -and $null -eq $prev) {
                $tokens = ConvertTo-CodexBreakdown $lastUsage
                $nextTotals = $totalUsage
            }
            elseif ($null -ne $totalUsage -and $null -eq $lastUsage -and $null -ne $prev) {
                if (Test-CodexTotalsEqual $totalUsage $prev) { continue }
                $d = Get-CodexTotalsDelta $totalUsage $prev
                if ($null -ne $d) {
                    $tokens = ConvertTo-CodexBreakdown $d
                    $nextTotals = $totalUsage
                }
                else {
                    $prev = $totalUsage
                    continue
                }
            }
            elseif ($null -ne $totalUsage -and $null -eq $lastUsage -and $null -eq $prev) {
                $tokens = ConvertTo-CodexBreakdown $totalUsage
                $nextTotals = $totalUsage
            }
            elseif ($null -eq $totalUsage -and $null -ne $lastUsage -and $null -ne $prev) {
                $tokens = ConvertTo-CodexBreakdown $lastUsage
                $nextTotals = Add-CodexTotals $prev $lastUsage
            }
            elseif ($null -eq $totalUsage -and $null -ne $lastUsage -and $null -eq $prev) {
                $tokens = ConvertTo-CodexBreakdown $lastUsage
                $nextTotals = $null
            }
            else {
                continue
            }

            if ($tokens.input -eq 0 -and $tokens.output -eq 0 -and $tokens.cache_read -eq 0 -and $tokens.reasoning -eq 0) { continue }

            $prev = $nextTotals
            $aggInput     += $tokens.input
            $aggOutput    += $tokens.output
            $aggCacheRead += $tokens.cache_read
            $aggCacheWrite += $tokens.cache_write
            $aggReasoning += $tokens.reasoning
        }
    } catch {
        return [pscustomobject]@{ Tokens=0; InputTokens=0; OutputTokens=0; CacheReadTokens=0; CacheWriteTokens=0; ReasoningTokens=0 }
    }

    $aggTotal = $aggInput + $aggOutput + $aggCacheRead + $aggCacheWrite + $aggReasoning
    return [pscustomobject]@{
        Tokens          = $aggTotal
        InputTokens     = $aggInput
        OutputTokens    = $aggOutput
        CacheReadTokens = $aggCacheRead
        CacheWriteTokens= $aggCacheWrite
        ReasoningTokens = $aggReasoning
    }
}

function Get-CodexSessions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $indexMap = Get-CodexSessionIndexMap -RootPath $RootPath
    $sessionFiles = Get-ChildItem -Path (Join-Path $RootPath 'sessions') -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue

    $records = foreach ($file in $sessionFiles) {
        $sessionId = Get-CodexSessionIdFromPath -Path $file.FullName
        if (-not $sessionId) {
            continue
        }

        $threadName = $null
        $indexedAt = $null
        $workspacePath = $null
        if ($indexMap.ContainsKey($sessionId)) {
            $threadName = $indexMap[$sessionId].ThreadName
            $indexedAt = $indexMap[$sessionId].UpdatedAt
        }

        $sessionMeta = Get-CodexSessionMeta -TranscriptPath $file.FullName
        if ($sessionMeta -and $sessionMeta.PSObject.Properties['cwd'] -and $sessionMeta.cwd) {
            $workspacePath = Repair-CodexMojibake $sessionMeta.cwd
        }

        $lane = Get-CodexLane -SessionMeta $sessionMeta
        $model = Get-CodexSessionModel -TranscriptPath $file.FullName
        $tokens = Get-CodexTokenUsage -TranscriptPath $file.FullName

        $lastActivity = if ($indexedAt -and $indexedAt -gt [DateTimeOffset]::MinValue) {
            $indexedAt.LocalDateTime
        } else {
            $file.LastWriteTime
        }

        [pscustomobject]@{
            Lane             = $lane
            SessionId        = $sessionId
            Title            = $threadName
            ThreadName       = $threadName
            LastActivity     = $lastActivity
            WorkspacePath    = $workspacePath
            Model            = $model
            Tokens           = $tokens.Tokens
            InputTokens      = $tokens.InputTokens
            OutputTokens     = $tokens.OutputTokens
            CacheReadTokens  = $tokens.CacheReadTokens
            CacheWriteTokens = $tokens.CacheWriteTokens
            ReasoningTokens  = $tokens.ReasoningTokens
            TranscriptPath   = $file.FullName
            ResumeCommand    = "codex resume $sessionId --dangerously-bypass-approvals-and-sandbox"
        }
    }

    @(
        $records |
            Sort-Object -Property LastActivity, SessionId -Descending |
            Group-Object SessionId |
            ForEach-Object { $_.Group[0] }
    )
}

# ============================================================================
# Claude 采集（移植自 claude-sessions.ps1 v1.2.9）
# ============================================================================
$ClaudeModelAliases = @{
    'big-pickle'                        = 'glm-4.7'
    'big pickle'                        = 'glm-4.7'
    'bigpickle'                         = 'glm-4.7'
    'k2p5'                              = 'kimi-k2-thinking'
    'k2-p5'                             = 'kimi-k2-thinking'
    'k2p6'                              = 'kimi-k2.6'
    'k2-p6'                             = 'kimi-k2.6'
    'kimi-k2p6'                         = 'kimi-k2.6'
    'kimi-k2.5-thinking'                = 'kimi-k2-thinking'
    'kimi-for-coding'                   = 'kimi-k2.5'
    'kimi-for-coding-highspeed'         = 'kimi-k2.7-code-highspeed'
    'k3'                                = 'kimi-k3'
    'model_placeholder_m26'             = 'claude-opus-4-6'
    'model_placeholder_m35'             = 'claude-sonnet-4-6'
    'model_placeholder_m36'             = 'gemini-3.1-pro'
    'model_placeholder_m37'             = 'gemini-3.1-pro'
    'model_placeholder_m16'             = 'gemini-3.1-pro'
    'model_placeholder_m18'             = 'gemini-3-flash-preview'
    'model_placeholder_m84'             = 'gemini-3-flash-preview'
    'model_placeholder_m132'            = 'gemini-3.5-flash-high'
    'model_placeholder_m133'            = 'gemini-3.5-flash-high'
    'model_placeholder_m187'            = 'gemini-3.5-flash-extra-low'
    'model_placeholder_m20'             = 'gemini-3.5-flash-medium'
    'gemini-pro-default'                = 'gemini-3.1-pro'
    'gemini-pro-agent'                  = 'gemini-3.1-pro'
    'gemini-3-flash-agent'              = 'gemini-3.5-flash-high'
    'gemini-3-flash-b'                  = 'gemini-3.5-flash-high'
    'gemini-3.5-flash-low'              = 'gemini-3.5-flash-medium'
    'model_placeholder_m47'             = 'gemini-3-flash-preview'
    'model_openai_gpt_oss_120b_medium' = 'gpt-oss-120b-medium'
    'claude-opus-4-6-thinking'          = 'claude-opus-4-6'
    'claude-sonnet-4-6-thinking'        = 'claude-sonnet-4-6'
    'claude-opus-4.6-thinking'          = 'claude-opus-4-6'
    'claude-sonnet-4.6-thinking'        = 'claude-sonnet-4-6'
    'claude-opus-4-6'                   = 'claude-opus-4-6'
    'claude-sonnet-4-6'                 = 'claude-sonnet-4-6'
    'claude-haiku-4-6'                  = 'claude-haiku-4-6'
    'claude-opus-4.6'                   = 'claude-opus-4-6'
    'claude-sonnet-4.6'                 = 'claude-sonnet-4-6'
    'claude-haiku-4.6'                  = 'claude-haiku-4-6'
    'anthropic/claude-4-5-opus'         = 'claude-opus-4-5'
    'anthropic/claude-4-5-sonnet'       = 'claude-sonnet-4-5'
    'anthropic/claude-4-5-haiku'        = 'claude-haiku-4-5'
    'anthropic/claude-4-6-opus'         = 'claude-opus-4-6'
    'anthropic/claude-4-6-sonnet'       = 'claude-sonnet-4-6'
    'anthropic/claude-4-6-haiku'        = 'claude-haiku-4-6'
    'gemini-3.1-pro-high'               = 'gemini-3.1-pro'
    'gemini-3.1-pro-low'                = 'gemini-3.1-pro'
    'gemini-3-pro-high'                 = 'gemini-3-pro'
    'gemini-3-pro-low'                  = 'gemini-3-pro'
    'gemini-3-flash'                    = 'gemini-3-flash-preview'
    'gemini-3-flash-c'                  = 'gemini-3-flash-preview'
    'gemini-3-flash-a'                  = 'gemini-3.5-flash-high'
    'grok-composer-2.5'                 = 'composer-2.5'
    'grok-composer-2.5-fast'            = 'composer-2.5-fast'
    'kimi-k2.5-nvfp4'                  = 'kimi-k2.5'
    'kimi-k2-instruct-0905'             = 'kimi-k2.5'
}

function Get-ClaudeCanonicalModel {
    param(
        [AllowNull()]
        [string]$Model
    )
    if ([string]::IsNullOrWhiteSpace($Model)) {
        return $Model
    }
    $key = $Model.ToLowerInvariant()
    if ($script:ClaudeModelAliases.ContainsKey($key)) {
        return $script:ClaudeModelAliases[$key]
    }
    return $Model
}

function Get-ClaudeTokenField {
    param($Obj, [string[]]$Keys)
    if ($null -eq $Obj) { return $null }
    foreach ($k in $Keys) {
        if ($Obj.PSObject.Properties[$k] -and $null -ne $Obj.$k) {
            $v = $Obj.$k
            if ($v -is [int] -or $v -is [long] -or $v -is [double] -or ($v -is [string] -and $v -match '^\d+$')) {
                return [long]$v
            }
        }
    }
    return $null
}

function Get-ClaudeSessionMeta {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        [string]$RoutingName
    )

    $lastTs = $null
    $workspacePath = $null
    $gitBranch = $null
    $mode = $null
    $messageCount = $null
    $customTitle = $null
    $modelId = $null
    $lastModel = $null
    $inputTokens = 0
    $outputTokens = 0
    $cacheReadTokens = 0
    $cacheWriteTokens = 0
    $claudeTokenDedup = @{}

    try {
        foreach ($line in [System.IO.File]::ReadLines($Path)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            $o = $null
            try {
                $o = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
            } catch {
                continue
            }
            if ($null -eq $o) {
                continue
            }

            if ($o.PSObject.Properties['timestamp'] -and $o.timestamp) {
                $lastTs = $o.timestamp
            }
            if ($o.PSObject.Properties['cwd'] -and $o.cwd) {
                $workspacePath = $o.cwd
            }
            if ($o.PSObject.Properties['gitBranch']) {
                $gitBranch = $o.gitBranch
            }
            if ($o.PSObject.Properties['messageCount']) {
                $messageCount = $o.messageCount
            }
            if ($o.PSObject.Properties['type'] -and $o.type -eq 'custom-title' -and $o.PSObject.Properties['customTitle'] -and $o.customTitle) {
                $customTitle = $o.customTitle
            }
            if ($null -eq $mode -and $o.PSObject.Properties['type'] -and $o.type -eq 'mode' -and $o.PSObject.Properties['mode']) {
                $mode = $o.mode
            }

            if (
                $o.PSObject.Properties['message'] -and $o.message -and
                $o.message.PSObject.Properties['model'] -and $o.message.model -is [string]
            ) {
                $m = $o.message.model
                if ($m -ne '<synthetic>' -and $m -ne '') {
                    $lastModel = $m
                }
            }

            if ($o.PSObject.Properties['type'] -and $o.type -eq 'assistant') {
                $usage = $null
                if ($o.PSObject.Properties['message'] -and $o.message -and $o.message.PSObject.Properties['usage']) {
                    $usage = $o.message.usage
                } elseif ($o.PSObject.Properties['usage']) {
                    $usage = $o.usage
                }
                if ($usage) {
                    $msgId = $null
                    $reqId = $null
                    if ($o.PSObject.Properties['message'] -and $o.message -and $o.message.PSObject.Properties['id']) {
                        $msgId = $o.message.id
                    }
                    if ($o.PSObject.Properties['requestId']) {
                        $reqId = $o.requestId
                    }
                    if ($msgId -and $reqId) {
                        $dedupKey = "$($msgId):$($reqId)"
                    } elseif ($msgId) {
                        $dedupKey = "message:$($msgId)"
                    } else {
                        $dedupKey = $null
                    }

                    $fi = (Get-ClaudeTokenField -Obj $usage -Keys @('input_tokens','inputTokens','prompt_tokens','promptTokenCount'))
                    $fo = (Get-ClaudeTokenField -Obj $usage -Keys @('output_tokens','outputTokens','completion_tokens','candidatesTokenCount'))
                    $fc = (Get-ClaudeTokenField -Obj $usage -Keys @('cache_read_input_tokens','cacheReadInputTokens','cacheTokens','prompt_cache_hit_tokens','cachedContentTokenCount'))
                    $fw = (Get-ClaudeTokenField -Obj $usage -Keys @('cache_creation_input_tokens','cachedWriteTokens','prompt_cache_write_tokens'))
                    $fi = $(if ($null -eq $fi) { 0 } else { [Math]::Max(0, $fi) })
                    $fo = $(if ($null -eq $fo) { 0 } else { [Math]::Max(0, $fo) })
                    $fc = $(if ($null -eq $fc) { 0 } else { [Math]::Max(0, $fc) })
                    $fw = $(if ($null -eq $fw) { 0 } else { [Math]::Max(0, $fw) })

                    if ($dedupKey -and $claudeTokenDedup.ContainsKey($dedupKey)) {
                        $d = $claudeTokenDedup[$dedupKey]
                        $d.input = [Math]::Max($d.input, $fi)
                        $d.output = [Math]::Max($d.output, $fo)
                        $d.cacheRead = [Math]::Max($d.cacheRead, $fc)
                        $d.cacheWrite = [Math]::Max($d.cacheWrite, $fw)
                    } elseif ($dedupKey) {
                        $claudeTokenDedup[$dedupKey] = [PSCustomObject]@{ input = $fi; output = $fo; cacheRead = $fc; cacheWrite = $fw }
                    } else {
                        $inputTokens += $fi
                        $outputTokens += $fo
                        $cacheReadTokens += $fc
                        $cacheWriteTokens += $fw
                    }
                }
            }
        }

        foreach ($d in $claudeTokenDedup.Values) {
            $inputTokens += $d.input
            $outputTokens += $d.output
            $cacheReadTokens += $d.cacheRead
            $cacheWriteTokens += $d.cacheWrite
        }
    } catch {
        return $null
    }

    $modelId = if ($lastModel) { Get-ClaudeCanonicalModel -Model $lastModel } else { $null }

    $lastActivity = $null
    if ($lastTs) {
        try {
            $parsedTimestamp = [DateTime]::Parse($lastTs, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $lastActivity = [DateTime]::SpecifyKind($parsedTimestamp, [DateTimeKind]::Utc).ToLocalTime()
        } catch {
            $lastActivity = $null
        }
    }
    if (-not $lastActivity) {
        try {
            $lastActivity = (Get-Item -LiteralPath $Path).LastWriteTime
        } catch {
            $lastActivity = [DateTime]::MinValue
        }
    }

    $title = $customTitle

    return [pscustomobject]@{
        SessionId    = $SessionId
        Title        = $title
        WorkspacePath = $workspacePath
        GitBranch    = $gitBranch
        Mode         = $mode
        LastActivity = $lastActivity
        MessageCount = $messageCount
        Model      = $modelId
        RoutingName  = $routingName
        Tokens       = $inputTokens + $outputTokens + $cacheReadTokens + $cacheWriteTokens
        InputTokens  = $inputTokens
        OutputTokens = $outputTokens
        CacheReadTokens = $cacheReadTokens
        CacheWriteTokens = $cacheWriteTokens
        ReasoningTokens = 0
    }
}

function ConvertTo-ClaudePowerShellLiteral {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return "''"
    }

    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-ClaudeResumeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        [AllowNull()]
        [string]$WorkspacePath
    )

    if (-not [string]::IsNullOrWhiteSpace($WorkspacePath)) {
        $quotedPath = ConvertTo-ClaudePowerShellLiteral -Value $WorkspacePath
        return "Set-Location -LiteralPath $quotedPath; claude --resume $SessionId --dangerously-skip-permissions"
    }

    return "claude --resume $SessionId --dangerously-skip-permissions"
}

function Get-ClaudeConfiguredModel {
    $candidates = @(
        (Join-Path $HOME '.claude' 'settings.json'),
        (Join-Path $HOME '.claude.json')
    )
    foreach ($p in $candidates) {
        if (-not (Test-Path -LiteralPath $p)) {
            continue
        }
        try {
            $cfg = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue
        } catch {
            continue
        }
        if ($null -eq $cfg) {
            continue
        }
        if ($cfg.PSObject.Properties['model'] -and -not [string]::IsNullOrWhiteSpace($cfg.model)) {
            return $cfg.model
        }
    }
    return $null
}

function Get-ClaudeSessions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $routingName = Get-ClaudeConfiguredModel
    $projectsRoot = Join-Path $RootPath 'projects'
    if (-not (Test-Path -LiteralPath $projectsRoot)) {
        return @()
    }

    $sessionFiles = Get-ChildItem -Path $projectsRoot -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue

    $records = foreach ($file in $sessionFiles) {
        $baseName = $file.BaseName
        if ($file.Name -eq 'journal.jsonl') {
            continue
        }
        $isAgent = $baseName -match '^agent-'

        $sessionId = $baseName
        $meta = Get-ClaudeSessionMeta -Path $file.FullName -SessionId $sessionId -RoutingName $routingName
        if ($null -eq $meta) {
            continue
        }

        $resumeCmd = $null
        if ($isAgent) {
            $agentType = $null
            $metaDir = Split-Path $file.FullName -Parent
            $metaPath = Join-Path -Path $metaDir -ChildPath ($baseName + '.meta.json')
            if (Test-Path -LiteralPath $metaPath) {
                try {
                    $mj = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($mj -and $mj.PSObject.Properties['agentType'] -and $mj.agentType) {
                        $agentType = $mj.agentType
                    }
                } catch { }
            }
            $label = if ($agentType) { $agentType } else { 'claude-code-subagent' }
            $shortId = $baseName -replace '^agent-', ''
            if ($shortId.Length -gt 8) { $shortId = $shortId.Substring(0, 8) }
            $meta.Title = "子智能体: $($label) ($($shortId))"
        } else {
            $resumeCmd = Get-ClaudeResumeCommand -SessionId $meta.SessionId -WorkspacePath $meta.WorkspacePath
        }

        [pscustomobject]@{
            SessionId      = $meta.SessionId
            Title          = $meta.Title
            WorkspacePath  = $meta.WorkspacePath
            RoutingName    = $meta.RoutingName
            GitBranch      = $meta.GitBranch
            Mode           = $meta.Mode
            LastActivity   = $meta.LastActivity
            MessageCount   = $meta.MessageCount
            Model        = $meta.Model
            Tokens         = $meta.Tokens
            InputTokens    = $meta.InputTokens
            OutputTokens   = $meta.OutputTokens
            CacheReadTokens= $meta.CacheReadTokens
            CacheWriteTokens = $meta.CacheWriteTokens
            ReasoningTokens = $meta.ReasoningTokens
            TranscriptPath = $file.FullName
            ResumeCommand  = $resumeCmd
        }
    }

    @($records)
}

# ============================================================================
# WorkBuddy 采集（移植自 workbuddy-sessions.ps1 v1.0.6，含内嵌 Python 只读桥接）
# ============================================================================
$pyCode = @'
import sqlite3, json, sys, os
from pathlib import Path

db = sys.argv[1]
out = sys.argv[2]
db_dir = os.path.dirname(os.path.abspath(db))
projects = os.path.join(db_dir, 'projects')
if not os.path.isdir(projects):
    projects = os.path.join(os.path.expanduser('~'), '.workbuddy', 'projects')

session_file_map = {}
if os.path.isdir(projects):
    for root, dirs, files in os.walk(projects):
        for fn in files:
            if fn.endswith('.jsonl'):
                sid = fn[:-6]
                if sid not in session_file_map:
                    session_file_map[sid] = os.path.join(root, fn)

def asnum(x):
    try: return int(float(x))
    except Exception: return 0

def _first_option(values):
    for v in values:
        if v is not None:
            return v
    return None

def _first_present(values):
    for v in values:
        if v is not None:
            return max(0, asnum(v))
    return 0

def _first_positive(values):
    found = None
    for v in values:
        if v is not None and asnum(v) > 0:
            found = asnum(v)
            break
    if found is None:
        for v in values:
            if v is not None:
                found = asnum(v)
                break
    return max(0, found) if found is not None else 0

def _input_exclusive(u, cache_read, cache_write, reasoning, output):
    miss = None
    if 'cachedMissTokens' in u and u['cachedMissTokens'] is not None:
        miss = max(0, u['cachedMissTokens'])
    elif 'cacheMissTokens' in u and u['cacheMissTokens'] is not None:
        miss = max(0, u['cacheMissTokens'])
    if miss is not None:
        return miss
    input_val = _first_present([u.get('input_tokens'), u.get('inputTokens'), u.get('prompt_tokens')])
    total = _first_option([u.get('total_tokens'), u.get('totalTokens')])
    if total is None:
        return input_val
    inclusive_total = input_val + output
    exclusive_total = inclusive_total + cache_read + cache_write + reasoning
    if cache_read > 0 and total == inclusive_total and inclusive_total != exclusive_total:
        return max(0, input_val - cache_read)
    return input_val

def _buddy_to_breakdown(u):
    cache_read = _first_positive([
        u.get('cache_read_input_tokens'), u.get('cacheReadInputTokens'),
        u.get('cacheTokens'), u.get('prompt_cache_hit_tokens'), u.get('cached_tokens'),
    ])
    output = _first_present([u.get('output_tokens'), u.get('outputTokens'), u.get('completion_tokens')])
    cache_write = _first_positive([
        u.get('cache_creation_input_tokens'), u.get('cacheCreationInputTokens'),
        u.get('cachedWriteTokens'), u.get('prompt_cache_write_tokens'),
    ])
    reasoning = _first_present([
        u.get('completion_thinking_tokens'), u.get('completionThinkingTokens'), u.get('reasoningTokens'),
    ])
    input_val = _input_exclusive(u, cache_read, cache_write, reasoning, output)
    total = input_val + output + cache_read + cache_write + reasoning
    if total <= 0:
        return None
    return dict(input=input_val, output=output, cache_read=cache_read,
                cache_write=cache_write, reasoning=reasoning, total=total)

def compute_tokens(jsonl_path):
    session_id = os.path.splitext(os.path.basename(jsonl_path))[0]
    keyed_indices = {}
    messages = []
    try:
        with open(jsonl_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if not isinstance(o, dict):
                    continue
                ltype = o.get('type')
                role = o.get('role')
                status = o.get('status')
                is_assistant = (ltype == 'message' and role == 'assistant')
                is_fc = (ltype == 'function_call')
                if not (is_assistant or is_fc):
                    continue
                if status is not None and status != 'completed':
                    continue
                u = None
                m = o.get('message') if isinstance(o.get('message'), dict) else None
                if isinstance(m, dict) and isinstance(m.get('usage'), dict):
                    u = m['usage']
                else:
                    pd = o.get('providerData') if isinstance(o.get('providerData'), dict) else None
                    if isinstance(pd, dict):
                        if isinstance(pd.get('usage'), dict):
                            u = pd['usage']
                        elif isinstance(pd.get('rawUsage'), dict):
                            u = pd['rawUsage']
                if not isinstance(u, dict):
                    continue
                tokens = _buddy_to_breakdown(u)
                if tokens is None:
                    continue
                pd = o.get('providerData') if isinstance(o.get('providerData'), dict) else None
                dedup_key = None
                if isinstance(pd, dict):
                    if pd.get('messageId'):
                        dedup_key = 'workbuddy:' + session_id + ':' + str(pd['messageId'])
                    elif pd.get('traceId'):
                        dedup_key = 'workbuddy:' + session_id + ':' + str(pd['traceId'])
                if dedup_key is None and o.get('id') is not None:
                    dedup_key = 'workbuddy:' + session_id + ':' + str(o['id'])
                if dedup_key is not None:
                    if dedup_key in keyed_indices:
                        idx = keyed_indices[dedup_key]
                        if tokens['total'] >= messages[idx]['total']:
                            messages[idx] = tokens
                        continue
                    keyed_indices[dedup_key] = len(messages)
                messages.append(tokens)
    except Exception:
        pass
    total = inp = outp = cr = cw = rs = 0
    for t in messages:
        total += t['total']
        inp += t['input']
        outp += t['output']
        cr += t['cache_read']
        cw += t['cache_write']
        rs += t['reasoning']
    return total, inp, outp, cr, cw, rs

uri = Path(db).resolve().as_uri() + '?mode=ro'
con = sqlite3.connect(uri, uri=True, timeout=5)
con.row_factory = sqlite3.Row
cur = con.cursor()
cur.execute("""
    SELECT s.id, s.title, s.custom_title, s.cwd, s.model,
           s.last_activity_at, s.updated_at, s.created_at,
           s.mode, s.source_mode, s.permission_mode, s.status, s.expert_id,
           s.is_background_automation, s.is_playground, s.deleted_at,
           COALESCE(su.used, 0) AS used_fallback
    FROM sessions s
    LEFT JOIN session_usage su ON su.session_id = s.id
""")
db_ids = set()
rows = []
for r in cur.fetchall():
    d = dict(r)
    sid = d['id']
    db_ids.add(sid)
    is_deleted = d.get('deleted_at') is not None
    total, inp, outp, cr, cw, rs = 0, 0, 0, 0, 0, 0
    jp = session_file_map.get(sid)
    if jp:
        total, inp, outp, cr, cw, rs = compute_tokens(jp)
    if is_deleted:
        if total == 0:
            continue
        base_title = d.get('custom_title') or d.get('title') or sid
        d['custom_title'] = base_title + ' [已软删除]'
    else:
        if total == 0:
            total = asnum(d.get('used_fallback'))
    d['token_source'] = 'used_fallback' if (jp is None and total > 0) else 'transcript'
    d['tokens'] = total
    d['input_tokens'] = inp
    d['output_tokens'] = outp
    d['cache_read_tokens'] = cr
    d['cache_write_tokens'] = cw
    d['reasoning_tokens'] = rs
    d['deleted'] = 1 if is_deleted else 0
    rows.append(d)

for sid, jp in session_file_map.items():
    if sid in db_ids:
        continue
    total, inp, outp, cr, cw, rs = compute_tokens(jp)
    if total == 0:
        continue
    is_agent = sid.startswith('agent-')
    model = ''
    try:
        with open(jp, 'r', encoding='utf-8') as _mf:
            for _line in _mf:
                try:
                    _o = json.loads(_line)
                except Exception:
                    continue
                if isinstance(_o, dict):
                    _m = _o.get('model')
                    if not _m and isinstance(_o.get('message'), dict):
                        _m = _o['message'].get('model')
                    if _m:
                        model = _m
                        break
    except Exception:
        pass
    _mtime = int(os.path.getmtime(jp) * 1000)
    d = {
        'id': sid,
        'title': None,
        'custom_title': ('子智能体: ' + sid) if is_agent else sid,
        'cwd': os.path.dirname(jp),
        'model': model,
        'last_activity_at': _mtime,
        'updated_at': _mtime,
        'created_at': _mtime,
        'mode': '',
        'source_mode': '',
        'permission_mode': '',
        'status': '',
        'expert_id': '',
        'is_background_automation': 1 if is_agent else 0,
        'is_playground': 0,
        'deleted_at': None,
        'used_fallback': 0,
        'token_source': 'transcript',
        'tokens': total,
        'input_tokens': inp,
        'output_tokens': outp,
        'cache_read_tokens': cr,
        'cache_write_tokens': cw,
        'reasoning_tokens': rs,
        'deleted': 0,
        'synthetic': 1,
    }
    rows.append(d)
with open(out, 'w', encoding='utf-8') as f:
    json.dump(rows, f, ensure_ascii=False)
con.close()
'@

function Get-WorkBuddyPython {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    $py = if ($cmd) { $cmd.Source } else { $null }
    if (-not $py) {
        $cmd = Get-Command py -ErrorAction SilentlyContinue
        $py = if ($cmd) { $cmd.Source } else { $null }
    }
    if ($py -and $py -match 'WindowsApps') {
        $probe = & $py --version 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { $py = $null }
    }
    if (-not $py) {
        $verRoot = Join-Path $HOME '.workbuddy' 'binaries' 'python' 'versions'
        if (Test-Path -LiteralPath $verRoot) {
            $py = Get-ChildItem -LiteralPath $verRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
                ForEach-Object {
                    $cand = Join-Path $_.FullName 'python.exe'
                    if (Test-Path -LiteralPath $cand) { $cand }
                } | Select-Object -First 1
        }
    }
    return $py
}

function Get-WorkBuddySessions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DbPath
    )

    if (-not (Test-Path -LiteralPath $DbPath)) {
        return @()
    }

    $py = Get-WorkBuddyPython
    if (-not $py) {
        throw '未找到 Python 解释器，无法读取 workbuddy.db（需要 python / py，或 WorkBuddy 自带运行时）。'
    }

    $prevPioEncoding = $env:PYTHONIOENCODING
    $env:PYTHONIOENCODING = 'utf-8'
    $tmpJson = Join-Path $env:TEMP ('wb-sessions-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $pyOutput = & $py -c $pyCode $DbPath $tmpJson 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $context = 'WorkBuddy 数据读取失败。数据库可能已升级、损坏，或 Python 桥接运行出错。'
            throw "$context`nPython 桥接错误（exit ${LASTEXITCODE}）：$($pyOutput.Trim())"
        }
        if (-not (Test-Path -LiteralPath $tmpJson)) {
            throw "Python 桥接未生成导出文件（workbuddy.db 结构可能与预期不符）：$($pyOutput.Trim())"
        }
        $raw = Get-Content -LiteralPath $tmpJson -Raw -Encoding UTF8
    } finally {
        $env:PYTHONIOENCODING = $prevPioEncoding
        Remove-Item -LiteralPath $tmpJson -Force -ErrorAction SilentlyContinue
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    $sessionRows = $raw | ConvertFrom-Json

    $records = foreach ($s in $sessionRows) {
        $title = if ($s.custom_title) { $s.custom_title } else { $s.title }
        $la = if ($s.last_activity_at) { $s.last_activity_at }
               elseif ($s.updated_at) { $s.updated_at }
               elseif ($s.created_at) { $s.created_at }
               else { $null }
        $lastActivity = $null
        if ($la) {
            try {
                $lastActivity = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$la).LocalDateTime
            } catch {
                $lastActivity = $null
            }
        }
        if (-not $lastActivity) {
            $lastActivity = [DateTime]::MinValue
        }

        $sessType = if ($s.is_playground -eq 1 -or $s.is_background_automation -eq 1) { '任务' } else { '空间' }

        [pscustomobject]@{
            SessionId       = $s.id
            Type            = $sessType
            Title           = $title
            WorkspacePath   = $s.cwd
            Model           = $s.model
            Tokens          = if ($s.tokens) { [long]$s.tokens } else { 0 }
            InputTokens     = if ($s.input_tokens) { [long]$s.input_tokens } else { 0 }
            OutputTokens    = if ($s.output_tokens) { [long]$s.output_tokens } else { 0 }
            CacheReadTokens = if ($s.cache_read_tokens) { [long]$s.cache_read_tokens } else { 0 }
            CacheWriteTokens= if ($s.cache_write_tokens) { [long]$s.cache_write_tokens } else { 0 }
            ReasoningTokens = if ($s.reasoning_tokens) { [long]$s.reasoning_tokens } else { 0 }
            TokenSource     = if ($s.token_source) { $s.token_source } else { 'transcript' }
            LastActivity    = $lastActivity
            Mode            = $s.mode
            SourceMode      = $s.source_mode
            PermissionMode  = $s.permission_mode
            Status          = $s.status
        }
    }

    if (@($records | Where-Object { $_.TokenSource -eq 'used_fallback' }).Count -gt 0) {
        Write-Warning '部分会话未找到 transcript，Tokens 已退化到 session_usage.used 兜底口径（仅供量级参考，不恒等式）。'
    }

    @($records)
}

# ============================================================================
# 统一帮助
# ============================================================================
function Show-AgentsSessionQueryHelp {
    @'
asq - 本机 Codex / Claude / WorkBuddy 历史会话统一查询命令

用法:
  asq <codex|claude|workbuddy> [选项]

  首个参数（或 -Source）必须指明查询哪一家的历史会话；它是唯一必填项：
    codex      查询 Codex / OMX 历史会话
    claude     查询 Claude Code 历史会话
    workbuddy  查询 WorkBuddy 历史会话（需 Python 桥接）
  最小可用写法：asq codex / asq claude / asq workbuddy，其余均为可选。

常用示例:
  asq workbuddy                      # 最近 20 条 WorkBuddy 会话（默认按当前路径过滤）
  asq claude -g                      # -g / -Global：全局模式，不按当前路径过滤
  asq codex -c                       # -c / -ShowCommands：详细视图（完整字段 + resume 命令）
  asq codex -q scripts               # -q：在 SessionId / Title / WorkspacePath 中模糊检索
  asq workbuddy -Type 任务           # -Type：按派生类型筛选（仅 workbuddy）
  asq claude -s <sessionId>          # -s：单会话完整详情（仅 claude / workbuddy）
  asq -Source codex -AsJson          # -AsJson：输出 JSON（多条为数组、单条为对象）
  asq codex 50                       # 位置参数 50 = 显示条数（等价于 -n 50）
  asq -h                             # 帮助：-h / -? / --help / help 均可
  asq -v                             # 版本号：-v / -Version（v1.1.0）

通用选项:
  -Source <codex|claude|workbuddy>   显式指定来源（等价于首个位置参数写法，如 asq codex）
  -g, -Global                        不按当前路径过滤，显示全局 session
  -r, -IncludeSubdirectories         在当前路径筛选中包含子目录 session
  -c, -ShowCommands                  详细命令视图（含会话路径、resume 命令等完整字段）
  -q, -SessionIdLike <检索词>        按 SessionId / Title / WorkspacePath 统一模糊筛选
  -t, -TitleLike <标题词>            仅按 Title 模糊筛选
  -o, -SortBy <LastActivity|WorkspacePath>   排序方式：LastActivity 按最近活动、WorkspacePath 按工作区路径（默认 LastActivity）
  -n, -Limit <N>                     限制输出条数（默认 20；也可直接写数字，如 asq codex 50）
  -AsJson                            输出 JSON（多条为数组、单条为对象）
  -WorkspacePath <路径>              指定筛选 session 工作区的路径（默认当前 PowerShell 路径）
  -h, -?, --help                     显示本帮助
  -v, -Version                       显示版本号

来源专属选项:
  -s, -SessionId <sessionId>         查看指定会话完整详情（忽略路径过滤；仅 claude / workbuddy）
  -RootPath <路径>                   Codex / Claude 数据根目录（仅 codex / claude；默认 ~/.codex 或 ~/.claude）
  -DbPath <路径>                     WorkBuddy 数据库文件路径（仅 workbuddy；默认 ~/.workbuddy/workbuddy.db）
  -Type <任务|空间>                   按派生类型筛选（仅 workbuddy：任务 / 空间）
'@
}

# ============================================================================
# 主流程
# ============================================================================
# 帮助令牌检测：兼容 -h / -? / --help / -help / help
#   这些令牌可能落在来源位(Source 位置参数)、Limit 位或未绑定余项(RemainingArgs)，逐一识别后强制进入帮助并复位对应参数，
#   避免 --help 被当成来源值触发“不支持的查询来源”。
$helpTokens = @('--help', '-help', 'help', '-h', '-?')
$forceHelp = $Help
if (($Source -is [string]) -and ($helpTokens -contains $Source)) {
    $forceHelp = $true
    $Source = $null
}
if (($Limit -is [string]) -and ($helpTokens -contains $Limit)) {
    $forceHelp = $true
    $Limit = 20
}
if (
    ($RemainingArgs -contains '--help') -or ($RemainingArgs -contains '-help') -or
    ($RemainingArgs -contains 'help') -or ($RemainingArgs -contains '-?') -or ($RemainingArgs -contains '-h')
) {
    $forceHelp = $true
}

# 版本令牌检测：兼容 --version / -version / version / -v
$versionTokens = @('--version', '-version', 'version', '-v')
$forceVersion = $Version
if (($Source -is [string]) -and ($versionTokens -contains $Source)) {
    $forceVersion = $true
    $Source = $null
}
if (($Limit -is [string]) -and ($versionTokens -contains $Limit)) {
    $forceVersion = $true
    $Limit = 20
}
if (
    ($RemainingArgs -contains '--version') -or ($RemainingArgs -contains '-version') -or
    ($RemainingArgs -contains 'version') -or ($RemainingArgs -contains '-v')
) {
    $forceVersion = $true
}

if ($forceHelp) {
    Show-AgentsSessionQueryHelp
    exit 0
}

if ($forceVersion) {
    Write-Output 'v1.1.0'
    exit 0
}

# 校验 -Source（含位置参数形式）：缺失或非法值 → 友好中文报错（exit 1，提示含 -Source）
$allowedSources = @('codex', 'claude', 'workbuddy')
if ([string]::IsNullOrWhiteSpace($Source) -or ($allowedSources -notcontains $Source)) {
    if ([string]::IsNullOrWhiteSpace($Source)) {
        Write-Output '缺少查询来源：请用 -Source codex|claude|workbuddy 或首个位置参数（如 asq codex）指定查询对象。运行 asq -h 查看完整帮助。'
    } else {
        Write-Output ('不支持的查询来源: {0}。可用来源: codex / claude / workbuddy（如 asq codex）。运行 asq -h 查看完整帮助。' -f $Source)
    }
    exit 1
}

# 参数用法容错：显示条数（Limit）只接受整数。若收到非数字，统一给出人话报错，列出本次实际用到的开关（含 -Source）。
if ($Limit -is [string] -and -not [string]::IsNullOrWhiteSpace($Limit) -and $Limit -notmatch '^\d+$') {
    $switchShortNames = @{
        Source               = '-Source'
        Global              = '-g'
        ShowCommands        = '-c'
        SessionIdLike       = '-q'
        TitleLike           = '-t'
        SessionId           = '-s'
        SortBy              = '-o'
        IncludeSubdirectories = '-r'
        AsJson              = '-AsJson'
        Help                = '-h'
        Type                = '-Type'
    }
    $usedSwitches = @(foreach ($key in $PSBoundParameters.Keys) {
        if ($switchShortNames.ContainsKey($key)) { $switchShortNames[$key] }
    })
    if ($usedSwitches.Count -eq 0) {
        $usedSwitches = @('-n')
    }
    Write-Output ('{0} 参数错误：只接受数字条数（如 asq codex 50 或 -n 50）。运行 asq -h 查看完整参数说明。' -f ($usedSwitches -join '、'))
    exit 1
}

try {
    $Limit = [int]$Limit
} catch {
    throw "Limit must be an integer. Use 'asq -Source $Source 50' or 'asq -Source $Source -n 50'."
}

$hasQuery = -not [string]::IsNullOrWhiteSpace($SessionIdLike)
$hasTitleQuery = -not [string]::IsNullOrWhiteSpace($TitleLike)
$hasSessionId = -not [string]::IsNullOrWhiteSpace($SessionId)
$hasTypeFilter = -not [string]::IsNullOrWhiteSpace($Type)
$hasAnyQuery = $hasQuery -or $hasTitleQuery -or $hasTypeFilter

# 按 Source 选择采集函数与数据源目录
$sourceLabel = $null
$dataSourceDir = $null
$sessions = $null
switch ($Source) {
    'codex' {
        $sourceLabel = 'Codex'
        $dataDir = if ($RootPath) { $RootPath } else { Join-Path $HOME '.codex' }
        $dataSourceDir = $dataDir
        $sessions = @(Get-CodexSessions -RootPath $dataDir)
    }
    'claude' {
        $sourceLabel = 'Claude Code'
        $dataDir = if ($RootPath) { $RootPath } else { Join-Path $HOME '.claude' }
        $dataSourceDir = $dataDir
        $sessions = @(Get-ClaudeSessions -RootPath $dataDir)
    }
    'workbuddy' {
        $sourceLabel = 'WorkBuddy'
        $dataDir = if ($DbPath) { $DbPath } else { Join-Path $HOME '.workbuddy\workbuddy.db' }
        $dataSourceDir = Split-Path -Parent $dataDir
        $sessions = @(Get-WorkBuddySessions -DbPath $dataDir)
    }
}

$rawSessionCount = @($sessions).Count
if ($rawSessionCount -eq 0) {
    if (-not (Test-Path -LiteralPath $dataSourceDir)) {
        Write-Output ('未检测到 {0} 数据目录（{1}），可能未安装或数据位于其他路径（可用 -RootPath/-DbPath 指定）。' -f $sourceLabel, $dataSourceDir)
    } else {
        Write-Output ('已检测到 {0} 数据目录（{1}），但未检索到任何 session 记录（可能尚未产生会话）。' -f $sourceLabel, $dataSourceDir)
    }
    exit 0
}

$currentWorkspace = $WorkspacePath
try {
    $resolvedWorkspace = Resolve-Path -LiteralPath $WorkspacePath -ErrorAction Stop
    $currentWorkspace = $resolvedWorkspace.ProviderPath
} catch {
}
$currentWorkspace = $currentWorkspace.TrimEnd('\', '/')

if ($hasSessionId -and ($Source -eq 'claude' -or $Source -eq 'workbuddy')) {
    $targetId = $SessionId.Trim().ToLowerInvariant()
    $matched = @($sessions | Where-Object { $_.SessionId -eq $targetId })
    if ($matched.Count -eq 0) {
        Write-Output ('未找到会话: {0}' -f $SessionId)
        exit 0
    }
    foreach ($session in $matched) {
        Write-Output ('-' * 80)
        if ($Source -eq 'claude') {
            Write-Output ('{0,-17} {1}' -f 'SessionId:', $session.SessionId)
            Write-Output ('{0,-17} {1}' -f 'LastActivity:', $session.LastActivity.ToString('yyyy-MM-dd HH:mm:ss'))
            Write-Output ('{0,-17} {1}' -f 'Title:', $session.Title)
            Write-Output ('{0,-17} {1}' -f 'WorkspacePath:', $session.WorkspacePath)
            Write-Output ('{0,-17} {1}' -f 'RoutingName:', $session.RoutingName)
            Write-Output ('{0,-17} {1}' -f 'Model:', $session.Model)
            Write-Output ('{0,-17} {1}' -f 'Tokens:', $session.Tokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'InputTokens:', $session.InputTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'OutputTokens:', $session.OutputTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'CacheReadTokens:', $session.CacheReadTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'CacheWriteTokens:', $session.CacheWriteTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'ReasoningTokens:', $session.ReasoningTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'GitBranch:', $session.GitBranch)
            Write-Output ('{0,-17} {1}' -f 'Mode:', $session.Mode)
            Write-Output ('{0,-17} {1}' -f 'MessageCount:', $session.MessageCount)
            Write-Output ('{0,-17} {1}' -f 'TranscriptPath:', $session.TranscriptPath)
            Write-Output ('{0,-17} {1}' -f 'ResumeCommand:', $session.ResumeCommand)
        } else {
            Write-Output ('{0,-17} {1}' -f 'SessionId:', $session.SessionId)
            Write-Output ('{0,-17} {1}' -f 'Type:', $session.Type)
            Write-Output ('{0,-17} {1}' -f 'LastActivity:', $session.LastActivity.ToString('yyyy-MM-dd HH:mm:ss'))
            Write-Output ('{0,-17} {1}' -f 'Title:', $session.Title)
            Write-Output ('{0,-17} {1}' -f 'WorkspacePath:', $session.WorkspacePath)
            Write-Output ('{0,-17} {1}' -f 'Model:', $session.Model)
            Write-Output ('{0,-17} {1}' -f 'Tokens:', $session.Tokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'InputTokens:', $session.InputTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'OutputTokens:', $session.OutputTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'CacheReadTokens:', $session.CacheReadTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'CacheWriteTokens:', $session.CacheWriteTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'ReasoningTokens:', $session.ReasoningTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'Mode:', $session.Mode)
            Write-Output ('{0,-17} {1}' -f 'SourceMode:', $session.SourceMode)
            Write-Output ('{0,-17} {1}' -f 'PermissionMode:', $session.PermissionMode)
            Write-Output ('{0,-17} {1}' -f 'Status:', $session.Status)
        }
    }
    Write-Output ('-' * 80)
    exit 0
}

$searchScope = if ($Global) {
    '全局'
} elseif ($IncludeSubdirectories) {
    '当前路径及子目录: {0}' -f $currentWorkspace
} else {
    '当前路径: {0}' -f $currentWorkspace
}

if (-not $Global) {
    if (-not [string]::IsNullOrWhiteSpace($currentWorkspace)) {
        $sessions = @(
            $sessions | Where-Object {
                if ([string]::IsNullOrWhiteSpace($_.WorkspacePath)) {
                    return $false
                }
                $sessionWorkspace = $_.WorkspacePath.TrimEnd('\', '/')
                (
                    $sessionWorkspace.Equals($currentWorkspace, [System.StringComparison]::OrdinalIgnoreCase) -or
                    (
                        $IncludeSubdirectories -and
                        $sessionWorkspace.StartsWith($currentWorkspace + '\', [System.StringComparison]::OrdinalIgnoreCase)
                    )
                )
            }
        )
    }
}

if ($hasQuery) {
    $keyword = $SessionIdLike.Trim().ToLowerInvariant()
    $sessions = @(
        $sessions | Where-Object {
            ($_.SessionId -and $_.SessionId.ToLowerInvariant().Contains($keyword)) -or
            ($_.Title -and $_.Title.ToLowerInvariant().Contains($keyword)) -or
            ($_.WorkspacePath -and $_.WorkspacePath.ToLowerInvariant().Contains($keyword))
        }
    )
}

if ($hasTitleQuery) {
    $titleKeyword = $TitleLike.Trim().ToLowerInvariant()
    $sessions = @(
        $sessions | Where-Object {
            $_.Title -and $_.Title.ToLowerInvariant().Contains($titleKeyword)
        }
    )
}

if ($hasTypeFilter -and $Source -eq 'workbuddy') {
    $sessions = @($sessions | Where-Object { $_.Type -eq $Type })
}

if ($SortBy -eq 'WorkspacePath') {
    $sessions = @(
        $sessions | Sort-Object `
            @{ Expression = { if ($_.WorkspacePath) { $_.WorkspacePath } else { '' } }; Descending = $false }, `
            @{ Expression = { $_.LastActivity }; Descending = $true }, `
            @{ Expression = { $_.SessionId }; Descending = $false }
    )
} else {
    $sessions = @(
        $sessions | Sort-Object `
            @{ Expression = { $_.LastActivity }; Descending = $true }, `
            @{ Expression = { $_.SessionId }; Descending = $false }
    )
}

if ($Limit -gt 0) {
    $sessions = @($sessions | Select-Object -First $Limit)
}

if (@($sessions).Count -eq 0) {
    if ($ShowCommands -or $hasAnyQuery) {
        if ($hasAnyQuery) {
            Write-Output ('检索范围: {0}' -f $searchScope)
        }
        Write-Output '未匹配到 session。'
        if ($hasQuery) {
            Write-Output ('检索词: {0}' -f $SessionIdLike)
        }
        if ($hasTitleQuery) {
            Write-Output ('标题检索词: {0}' -f $TitleLike)
        }
        if ($hasTypeFilter) {
            Write-Output ('类型筛选: {0}' -f $Type)
        }
        if ($hasAnyQuery) {
            if ($Global) {
                Write-Output '建议：尝试缩短关键词，或改用更稳定的 Title 片段。'
            } else {
                Write-Output '建议：尝试缩短关键词，或加 -g 在全局 session 中检索。'
            }
        }
        exit 0
    }
}

if ($AsJson) {
    if ($Source -eq 'codex') {
        $payload = $sessions | ForEach-Object {
            [pscustomobject]@{
                Lane             = $_.Lane
                SessionId        = $_.SessionId
                Title            = $_.Title
                ThreadName       = $_.ThreadName
                LastActivity     = $_.LastActivity.ToString('yyyy-MM-dd HH:mm:ss')
                WorkspacePath    = $_.WorkspacePath
                Model            = $_.Model
                Tokens           = $_.Tokens
                InputTokens      = $_.InputTokens
                OutputTokens     = $_.OutputTokens
                CacheReadTokens  = $_.CacheReadTokens
                CacheWriteTokens = $_.CacheWriteTokens
                ReasoningTokens  = $_.ReasoningTokens
                TranscriptPath   = $_.TranscriptPath
                ResumeCommand    = $_.ResumeCommand
            }
        }
    } elseif ($Source -eq 'claude') {
        $payload = $sessions | ForEach-Object {
            [pscustomobject]@{
                SessionId      = $_.SessionId
                Title          = $_.Title
                WorkspacePath  = $_.WorkspacePath
                GitBranch      = $_.GitBranch
                Mode           = $_.Mode
                LastActivity   = $_.LastActivity.ToString('yyyy-MM-dd HH:mm:ss')
                MessageCount   = $_.MessageCount
                RoutingName    = $_.RoutingName
                Model        = $_.Model
                Tokens         = $_.Tokens
                InputTokens    = $_.InputTokens
                OutputTokens   = $_.OutputTokens
                CacheReadTokens= $_.CacheReadTokens
                CacheWriteTokens = $_.CacheWriteTokens
                ReasoningTokens = $_.ReasoningTokens
                TranscriptPath = $_.TranscriptPath
                ResumeCommand  = $_.ResumeCommand
            }
        }
    } else {
        $payload = $sessions | ForEach-Object {
            [pscustomobject]@{
                SessionId       = $_.SessionId
                Type            = $_.Type
                Title           = $_.Title
                WorkspacePath   = $_.WorkspacePath
                Model           = $_.Model
                Tokens          = $_.Tokens
                TokenSource     = $_.TokenSource
                InputTokens     = $_.InputTokens
                OutputTokens    = $_.OutputTokens
                CacheReadTokens = $_.CacheReadTokens
                CacheWriteTokens= $_.CacheWriteTokens
                ReasoningTokens = $_.ReasoningTokens
                LastActivity    = $_.LastActivity.ToString('yyyy-MM-dd HH:mm:ss')
                Mode            = $_.Mode
                SourceMode      = $_.SourceMode
                PermissionMode  = $_.PermissionMode
                Status          = $_.Status
            }
        }
    }
    $payload | ConvertTo-Json -Depth 5 -Compress
    exit 0
}

if ($ShowCommands) {
    if ($hasAnyQuery) {
        Write-Output ('检索范围: {0}' -f $searchScope)
    }
    foreach ($session in $sessions) {
        Write-Output ('-' * 80)
        if ($Source -eq 'codex') {
            Write-Output ('{0,-17} {1}' -f 'Lane:', $session.Lane)
            Write-Output ('{0,-17} {1}' -f 'SessionId:', $session.SessionId)
            Write-Output ('{0,-17} {1}' -f 'LastActivity:', $session.LastActivity.ToString('yyyy-MM-dd HH:mm:ss'))
            Write-Output ('{0,-17} {1}' -f 'Title:', $session.Title)
            Write-Output ('{0,-17} {1}' -f 'WorkspacePath:', $session.WorkspacePath)
            Write-Output ('{0,-17} {1}' -f 'Model:', $session.Model)
            Write-Output ('{0,-17} {1}' -f 'Tokens:', $session.Tokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'InputTokens:', $session.InputTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'OutputTokens:', $session.OutputTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'CacheReadTokens:', $session.CacheReadTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'CacheWriteTokens:', $session.CacheWriteTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'ReasoningTokens:', $session.ReasoningTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'ResumeCommand:', $session.ResumeCommand)
        } elseif ($Source -eq 'claude') {
            Write-Output ('{0,-17} {1}' -f 'SessionId:', $session.SessionId)
            Write-Output ('{0,-17} {1}' -f 'LastActivity:', $session.LastActivity.ToString('yyyy-MM-dd HH:mm:ss'))
            Write-Output ('{0,-17} {1}' -f 'Title:', $session.Title)
            Write-Output ('{0,-17} {1}' -f 'WorkspacePath:', $session.WorkspacePath)
            Write-Output ('{0,-17} {1}' -f 'RoutingName:', $session.RoutingName)
            Write-Output ('{0,-17} {1}' -f 'Model:', $session.Model)
            Write-Output ('{0,-17} {1}' -f 'Tokens:', $session.Tokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'InputTokens:', $session.InputTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'OutputTokens:', $session.OutputTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'CacheReadTokens:', $session.CacheReadTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'CacheWriteTokens:', $session.CacheWriteTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'ReasoningTokens:', $session.ReasoningTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'GitBranch:', $session.GitBranch)
            Write-Output ('{0,-17} {1}' -f 'Mode:', $session.Mode)
            Write-Output ('{0,-17} {1}' -f 'MessageCount:', $session.MessageCount)
            Write-Output ('{0,-17} {1}' -f 'TranscriptPath:', $session.TranscriptPath)
            Write-Output ('{0,-17} {1}' -f 'ResumeCommand:', $session.ResumeCommand)
        } else {
            Write-Output ('{0,-17} {1}' -f 'SessionId:', $session.SessionId)
            Write-Output ('{0,-17} {1}' -f 'Type:', $session.Type)
            Write-Output ('{0,-17} {1}' -f 'LastActivity:', $session.LastActivity.ToString('yyyy-MM-dd HH:mm:ss'))
            Write-Output ('{0,-17} {1}' -f 'Title:', $session.Title)
            Write-Output ('{0,-17} {1}' -f 'WorkspacePath:', $session.WorkspacePath)
            Write-Output ('{0,-17} {1}' -f 'Model:', $session.Model)
            Write-Output ('{0,-17} {1}' -f 'Tokens:', $session.Tokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'InputTokens:', $session.InputTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'OutputTokens:', $session.OutputTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'CacheReadTokens:', $session.CacheReadTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'CacheWriteTokens:', $session.CacheWriteTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'ReasoningTokens:', $session.ReasoningTokens.ToString('N0'))
            Write-Output ('{0,-17} {1}' -f 'Mode:', $session.Mode)
            Write-Output ('{0,-17} {1}' -f 'SourceMode:', $session.SourceMode)
            Write-Output ('{0,-17} {1}' -f 'PermissionMode:', $session.PermissionMode)
            Write-Output ('{0,-17} {1}' -f 'Status:', $session.Status)
        }
    }
    Write-Output ('-' * 80)
    exit 0
}

# 表格渲染（按 Source 列布局；统一 Format-SessionCell 截断对齐）
$consoleWidth = 120
try {
    if ($Host -and $Host.UI -and $Host.UI.RawUI) {
        $consoleWidth = [Math]::Max([int]$Host.UI.RawUI.WindowSize.Width, 80)
    }
} catch {
}

if ($Source -eq 'codex') {
    $widths = @{ Lane = 5; SessionId = 36; LastActivity = 19; Model = 24; Tokens = 14 }
    $numColumns = 7
    $fixedWidth = $widths.Lane + $widths.SessionId + $widths.LastActivity + $widths.Model + $widths.Tokens + ($numColumns - 1)
    $remainingWidth = [Math]::Max($consoleWidth - $fixedWidth, 56)
    $titleWidth = [Math]::Max([Math]::Min(32, [Math]::Floor($remainingWidth * 0.35)), 18)
    $workspaceWidth = [Math]::Max($remainingWidth - $titleWidth, 20)
    $widths.Title = $titleWidth
    $widths.WorkspacePath = $workspaceWidth

    $header = '{0} {1} {2} {3} {4} {5} {6}' -f `
        (Format-SessionCell -Text 'Lane' -Width $widths.Lane), `
        (Format-SessionCell -Text 'SessionId' -Width $widths.SessionId), `
        (Format-SessionCell -Text 'LastActivity' -Width $widths.LastActivity), `
        (Format-SessionCell -Text 'Title' -Width $widths.Title), `
        (Format-SessionCell -Text 'Model' -Width $widths.Model), `
        (Format-SessionCell -Text 'Tokens' -Width $widths.Tokens -Align right), `
        (Format-SessionCell -Text 'WorkspacePath' -Width $widths.WorkspacePath)
    $separator = '{0} {1} {2} {3} {4} {5} {6}' -f `
        ('-' * $widths.Lane), ('-' * $widths.SessionId), ('-' * $widths.LastActivity), ('-' * $widths.Title), ('-' * $widths.Model), ('-' * $widths.Tokens), ('-' * $widths.WorkspacePath)
    if ($hasAnyQuery) { Write-Output ('检索范围: {0}' -f $searchScope) }
    Write-Output $header
    Write-Output $separator
    foreach ($session in $sessions) {
        $line = '{0} {1} {2} {3} {4} {5} {6}' -f `
            (Format-SessionCell -Text $session.Lane -Width $widths.Lane), `
            (Format-SessionCell -Text $session.SessionId -Width $widths.SessionId), `
            (Format-SessionCell -Text ($session.LastActivity.ToString('yyyy-MM-dd HH:mm:ss')) -Width $widths.LastActivity), `
            (Format-SessionCell -Text $session.Title -Width $widths.Title), `
            (Format-SessionCell -Text $session.Model -Width $widths.Model), `
            (Format-SessionCell -Text ($session.Tokens.ToString('N0')) -Width $widths.Tokens -Align right), `
            (Format-SessionCell -Text $session.WorkspacePath -Width $widths.WorkspacePath -Mode 'middle')
        Write-Output $line
    }
} elseif ($Source -eq 'claude') {
    $widths = @{ SessionId = 36; LastActivity = 16; Model = 24; Tokens = 14 }
    $numColumns = 6
    $fixedWidth = $widths.SessionId + $widths.LastActivity + $widths.Model + $widths.Tokens + ($numColumns - 1)
    $remainingWidth = [Math]::Max($consoleWidth - $fixedWidth, 56)
    $titleWidth = [Math]::Max([Math]::Min(40, [Math]::Floor($remainingWidth * 0.45)), 20)
    $workspaceWidth = [Math]::Max($remainingWidth - $titleWidth - 2, 20)
    $widths.Title = $titleWidth
    $widths.WorkspacePath = $workspaceWidth

    $header = '{0} {1} {2} {3} {4} {5}' -f `
        (Format-SessionCell -Text 'SessionId' -Width $widths.SessionId), `
        (Format-SessionCell -Text 'LastActivity' -Width $widths.LastActivity), `
        (Format-SessionCell -Text 'Title' -Width $widths.Title), `
        (Format-SessionCell -Text 'Model' -Width $widths.Model), `
        (Format-SessionCell -Text 'Tokens' -Width $widths.Tokens -Align right), `
        (Format-SessionCell -Text 'WorkspacePath' -Width $widths.WorkspacePath)
    $separator = '{0} {1} {2} {3} {4} {5}' -f `
        ('-' * $widths.SessionId), ('-' * $widths.LastActivity), ('-' * $widths.Title), ('-' * $widths.Model), ('-' * $widths.Tokens), ('-' * $widths.WorkspacePath)
    if ($hasAnyQuery) { Write-Output ('检索范围: {0}' -f $searchScope) }
    Write-Output $header
    Write-Output $separator
    foreach ($session in $sessions) {
        $line = '{0} {1} {2} {3} {4} {5}' -f `
            (Format-SessionCell -Text $session.SessionId -Width $widths.SessionId), `
            (Format-SessionCell -Text ($session.LastActivity.ToString('yyyy-MM-dd HH:mm')) -Width $widths.LastActivity), `
            (Format-SessionCell -Text $session.Title -Width $widths.Title), `
            (Format-SessionCell -Text $session.Model -Width $widths.Model), `
            (Format-SessionCell -Text ($session.Tokens.ToString('N0')) -Width $widths.Tokens -Align right), `
            (Format-SessionCell -Text $session.WorkspacePath -Width $widths.WorkspacePath -Mode 'middle')
        Write-Output $line
    }
} else {
    $widths = @{ Type = 5; SessionId = 36; LastActivity = 19; Model = 20; Tokens = 14 }
    $numColumns = 7
    $fixedWidth = $widths.Type + $widths.SessionId + $widths.LastActivity + $widths.Model + $widths.Tokens + ($numColumns - 1)
    $remainingWidth = [Math]::Max($consoleWidth - $fixedWidth, 56)
    $titleWidth = [Math]::Max([Math]::Min(32, [Math]::Floor($remainingWidth * 0.35)), 18)
    $workspaceWidth = [Math]::Max($remainingWidth - $titleWidth, 20)
    $widths.Title = $titleWidth
    $widths.WorkspacePath = $workspaceWidth

    $header = '{0} {1} {2} {3} {4} {5} {6}' -f `
        (Format-SessionCell -Text 'Type' -Width $widths.Type), `
        (Format-SessionCell -Text 'SessionId' -Width $widths.SessionId), `
        (Format-SessionCell -Text 'LastActivity' -Width $widths.LastActivity), `
        (Format-SessionCell -Text 'Title' -Width $widths.Title), `
        (Format-SessionCell -Text 'Model' -Width $widths.Model), `
        (Format-SessionCell -Text 'Tokens' -Width $widths.Tokens -Align right), `
        (Format-SessionCell -Text 'WorkspacePath' -Width $widths.WorkspacePath)
    $separator = '{0} {1} {2} {3} {4} {5} {6}' -f `
        ('-' * $widths.Type), ('-' * $widths.SessionId), ('-' * $widths.LastActivity), ('-' * $widths.Title), ('-' * $widths.Model), ('-' * $widths.Tokens), ('-' * $widths.WorkspacePath)
    if ($hasAnyQuery) { Write-Output ('检索范围: {0}' -f $searchScope) }
    Write-Output $header
    Write-Output $separator
    foreach ($session in $sessions) {
        $line = '{0} {1} {2} {3} {4} {5} {6}' -f `
            (Format-SessionCell -Text $session.Type -Width $widths.Type), `
            (Format-SessionCell -Text $session.SessionId -Width $widths.SessionId), `
            (Format-SessionCell -Text ($session.LastActivity.ToString('yyyy-MM-dd HH:mm:ss')) -Width $widths.LastActivity), `
            (Format-SessionCell -Text $session.Title -Width $widths.Title), `
            (Format-SessionCell -Text $session.Model -Width $widths.Model), `
            (Format-SessionCell -Text ($session.Tokens.ToString('N0')) -Width $widths.Tokens -Align right), `
            (Format-SessionCell -Text $session.WorkspacePath -Width $widths.WorkspacePath -Mode 'middle')
        Write-Output $line
    }
}
