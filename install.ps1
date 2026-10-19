# Clawd Pet 安装脚本：把小宠物放进 ~/.claude/clawd-pet，并在 ~/.claude/settings.json 里加上 3 个 hook。
# 重复运行是安全的：旧的 Clawd hook 会先被替换掉。
param([string]$ClaudeDir = (Join-Path $HOME '.claude'))
$ErrorActionPreference = 'Stop'
$dest = Join-Path $ClaudeDir 'clawd-pet'
$settingsPath = Join-Path $ClaudeDir 'settings.json'

New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'clawd.ps1'), (Join-Path $PSScriptRoot 'mood.ps1') $dest -Force

if (Test-Path $settingsPath) {
  Copy-Item $settingsPath "$settingsPath.bak-clawd" -Force
  $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
  $settings = [pscustomobject]@{}
}
if (-not $settings.PSObject.Properties['hooks']) { $settings | Add-Member hooks ([pscustomobject]@{}) }

$mood = ($dest -replace '\\', '/') + '/mood.ps1'
$wanted = [ordered]@{ SessionStart = 'idle'; UserPromptSubmit = 'working'; Stop = 'done' }
foreach ($event in $wanted.Keys) {
  $hook = [pscustomobject]@{
    hooks = @([pscustomobject]@{
      type = 'command'
      command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$mood`" $($wanted[$event])"
      timeout = 10
      async = $true
    })
  }
  $kept = @()
  if ($settings.hooks.PSObject.Properties[$event]) {
    $kept = @($settings.hooks.$event | Where-Object { -not (($_.hooks | ForEach-Object { $_.command }) -match 'clawd-pet') })
  }
  $settings.hooks | Add-Member $event (@($kept) + $hook) -Force
}

$json = $settings | ConvertTo-Json -Depth 32
[IO.File]::WriteAllText($settingsPath, $json, [Text.UTF8Encoding]::new($false))

& (Join-Path $dest 'mood.ps1') idle
Write-Host '装好啦！Clawd 在屏幕右下角。新开一个 Claude Code 会话就会跟着动起来。' -ForegroundColor Green
