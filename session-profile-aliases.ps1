<#
AgentsSessionQuery 套件 · 统一命令注册脚本
版本: v1.4.0
更新日期: 2026-09-03
说明: 注册统一命令 asq（Agents Sessions Query），供本机 PowerShell Profile 点加载；新开终端即可直接调用 asq。
      v1.4.0 起套件收敛为单一入口 asq：codex-sessions / claude-sessions / workbuddy-sessions 三个旧子命令及其
      wrapper脚本已退役删除。此前三者以 wrapper前向转发 asq.ps1 -Source codex|claude|workbuddy，
      现统一以来源位置参数或 -Source 调用，例如：asq codex -g、asq -Source workbuddy -Type 任务。
      全部采集 / token 解析 / 过滤 / 排序 / 输出逻辑均位于 asq.ps1（唯一真源）。
详细记录: CHANGELOG.md
历史:
  v1.4.0 — 移除 codex-sessions / claude-sessions / workbuddy-sessions 三个子命令注册（对应 wrapper脚本
           codex-sessions.ps1 / claude-sessions.ps1 / workbuddy-sessions.ps1 一并退役删除），仅注册统一命令 asq；
           查询一律以 asq <codex|claude|workbuddy> [选项] 进行，帮助见 asq -h。
  v1.3.4 — 注册统一命令 asq：新增 function asq 透传至 asq.ps1（其已处理 -Source / 位置来源 / 五种帮助令牌），补全 v0.2 重构遗漏（此前 asq 未被注册为 Profile 命令，README/CHANGELOG 的 asq 示例无法直呼）。
#>

$script:AgentsSessionQueryScript = Join-Path $PSScriptRoot 'asq.ps1'

function asq {
    & $script:AgentsSessionQueryScript @args
}
