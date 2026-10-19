# Called by Claude Code hooks: sets Clawd's mood and makes sure the floating window is up.
param([string]$Mood = 'idle')
$says = @{ idle = '摸鱼中～有事叫我'; working = '干活中…'; done = '做好啦！点我回去' }
$text = $says[$Mood]
[IO.File]::WriteAllText("$PSScriptRoot\state.txt", "$Mood`t$text", [Text.UTF8Encoding]::new($false))
$m = $null
if (-not [Threading.Mutex]::TryOpenExisting('Global\ClawdPetWindow', [ref]$m)) {
  Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSScriptRoot\clawd.ps1`""
} else { $m.Dispose() }