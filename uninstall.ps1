# Clawd Pet 卸载脚本：关掉小宠物，删掉 hook 和文件。
param([string]$ClaudeDir = (Join-Path $HOME '.claude'))
$ErrorActionPreference = 'Stop'
$dest = Join-Path $ClaudeDir 'clawd-pet'
$settingsPath = Join-Path $ClaudeDir 'settings.json'

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*clawd.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

if (Test-Path $settingsPath) {
  $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($settings.PSObject.Properties['hooks']) {
    foreach ($event in @($settings.hooks.PSObject.Properties.Name)) {
      $kept = @($settings.hooks.$event | Where-Object { -not (($_.hooks | ForEach-Object { $_.command }) -match 'clawd-pet') })
      if ($kept.Count) { $settings.hooks | Add-Member $event $kept -Force } else { $settings.hooks.PSObject.Properties.Remove($event) }
    }
    if (-not @($settings.hooks.PSObject.Properties).Count) { $settings.PSObject.Properties.Remove('hooks') }
  }
  [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 32), [Text.UTF8Encoding]::new($false))
}

if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
Write-Host 'Clawd 已经回家了，拜拜～' -ForegroundColor Yellow
